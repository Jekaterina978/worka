/**
 * AI Parser module — two-stage pipeline.
 *
 * Stage 1 (AI)  : semantic extraction — free-text fields, no enum constraints.
 * Stage 2 (code): deterministic normalization — maps free text to final schema.
 *
 * Public API (unchanged):
 *   parseVacancyText(text) → Promise<object>
 *   parseCVText(text)      → Promise<object>
 *
 * Environment variable required:
 *   OPENAI_API_KEY
 */

'use strict';

const OpenAI = require('openai');

// ─── OpenAI client ────────────────────────────────────────────────────────────

function getClient() {
  const key = (process.env.OPENAI_API_KEY || '').trim();
  if (!key) {
    throw new Error(
      'OPENAI_API_KEY is not configured. ' +
      'Set it in functions/.env (local) or as a Cloud Run env var / Firebase Secret (production).',
    );
  }
  return new OpenAI({ apiKey: key });
}

// ─── Language detection (heuristic, no AI call) ───────────────────────────────

/**
 * Detect source language from character statistics.
 * Returns 'ru' | 'uk' | 'en' | 'et' | null.
 */
function detectLanguage(text) {
  if (!text || text.length < 20) return null;
  const sample = text.slice(0, 600);
  const cyrillic = (sample.match(/[а-яёА-ЯЁ]/g) || []).length;
  const latin    = (sample.match(/[a-zA-Z]/g)    || []).length;
  const total    = cyrillic + latin;
  if (total === 0) return null;

  if (cyrillic / total > 0.4) {
    // Distinguish Ukrainian by specific chars (і, ї, є, ґ)
    const uk = (sample.match(/[іїєґІЇЄҐ]/g) || []).length;
    return uk > 3 ? 'uk' : 'ru';
  }
  if (cyrillic / total < 0.1) {
    // Estonian-specific chars (ä, ö, ü, õ)
    const et = (sample.match(/[äöüõÄÖÜÕ]/g) || []).length;
    return et > 2 ? 'et' : 'en';
  }
  return null;
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

function clean(v) {
  if (v === null || v === undefined) return null;
  const s = String(v).trim();
  return s.length > 0 ? s : null;
}

function toBool(v) {
  if (typeof v === 'boolean') return v;
  if (v === 'true'  || v === 1) return true;
  if (v === 'false' || v === 0) return false;
  return null;
}

function toNum(v) {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) && n >= 0 ? n : null;
}

function cleanArray(arr) {
  if (!Array.isArray(arr)) return [];
  const seen = new Set();
  return arr.reduce((out, item) => {
    const s = clean(item);
    if (s) {
      const key = s.toLowerCase();
      if (!seen.has(key)) { seen.add(key); out.push(s); }
    }
    return out;
  }, []);
}

/**
 * Trim text to maxLen characters at the last sentence boundary.
 */
function trimToLength(v, maxLen) {
  const s = clean(v);
  if (!s || s.length <= maxLen) return s;
  const cut = s.slice(0, maxLen);
  const dot = Math.max(cut.lastIndexOf('. '), cut.lastIndexOf('.\n'));
  if (dot > maxLen * 0.55) return cut.slice(0, dot + 1).trim();
  return cut.trim() + '…';
}

// ─── Date normalization (handles Russian month names) ─────────────────────────

const RU_MONTH_MAP = {
  'январ': '01', 'феврал': '02', 'март': '03', 'апрел': '04',
  'мая': '05',   'май':   '05',  'июн':  '06', 'июл':   '07',
  'август': '08', 'сентябр': '09', 'октябр': '10',
  'ноябр': '11', 'декабр': '12',
};

function cleanDate(raw) {
  const s = clean(raw);
  if (!s) return null;

  // Already canonical: YYYY, YYYY-MM, YYYY-MM-DD
  if (/^\d{4}(-\d{2}(-\d{2})?)?$/.test(s)) return s;

  // Russian month names
  const lc = s.toLowerCase();
  for (const [stem, num] of Object.entries(RU_MONTH_MAP)) {
    if (lc.includes(stem)) {
      const y = s.match(/\d{4}/);
      return y ? `${y[0]}-${num}` : null;
    }
  }

  // MM/YYYY or MM.YYYY
  const mmYYYY = s.match(/^(\d{1,2})[\/.](\d{4})$/);
  if (mmYYYY) return `${mmYYYY[2]}-${mmYYYY[1].padStart(2, '0')}`;

  // YYYY/MM or YYYY.MM
  const YYYYmm = s.match(/^(\d{4})[\/.](\d{1,2})$/);
  if (YYYYmm) return `${YYYYmm[1]}-${YYYYmm[2].padStart(2, '0')}`;

  // Generic JS parse (English month names, ISO strings)
  try {
    const d = new Date(s);
    if (!Number.isNaN(d.getTime()) && d.getFullYear() > 1950) {
      return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    }
  } catch { /* ignore */ }

  return null;
}

// ─── Country normalization (English/Estonian → Russian) ──────────────────────

const EN_TO_RU_COUNTRY = {
  'estonia': 'Эстония',      'eesti': 'Эстония',
  'finland': 'Финляндия',    'suomi': 'Финляндия',
  'germany': 'Германия',     'deutschland': 'Германия',
  'latvia':  'Латвия',       'latvija': 'Латвия',
  'lithuania': 'Литва',      'lietuva': 'Литва',
  'poland':  'Польша',       'polska': 'Польша',
  'ukraine': 'Украина',
  'russia':  'Россия',       'russian federation': 'Россия',
  'sweden':  'Швеция',       'sverige': 'Швеция',
  'norway':  'Норвегия',     'norge': 'Норвегия',
  'denmark': 'Дания',        'danmark': 'Дания',
  'netherlands': 'Нидерланды', 'holland': 'Нидерланды',
  'belgium': 'Бельгия',
  'france':  'Франция',
  'spain':   'Испания',      'espana': 'Испания',
  'italy':   'Италия',       'italia': 'Италия',
  'czech':   'Чехия',        'czechia': 'Чехия', 'czech republic': 'Чехия',
  'austria': 'Австрия',
  'switzerland': 'Швейцария',
  'uk':      'Великобритания', 'united kingdom': 'Великобритания', 'britain': 'Великобритания',
  'usa':     'США',          'united states': 'США',
  'canada':  'Канада',
  'australia': 'Австралия',
  'israel':  'Израиль',
  'portugal': 'Португалия',
  'hungary': 'Венгрия',
  'romania': 'Румыния',
  'bulgaria': 'Болгария',
  'croatia': 'Хорватия',
  'slovakia': 'Словакия',
  'moldova': 'Молдова',
  'belarus': 'Беларусь',
  'georgia': 'Грузия',
  'armenia': 'Армения',
  'azerbaijan': 'Азербайджан',
  'kazakhstan': 'Казахстан',
  'ireland': 'Ирландия',
  'greece':  'Греция',
  'cyprus':  'Кипр',
  'luxembourg': 'Люксембург',
  'serbia':  'Сербия',
};

const RU_KNOWN_COUNTRIES = new Set(Object.values(EN_TO_RU_COUNTRY));

function normalizeCountryToRu(text) {
  if (!text) return null;
  const t = text.trim();
  if (RU_KNOWN_COUNTRIES.has(t)) return t;            // already Russian
  const lc = t.toLowerCase();
  if (EN_TO_RU_COUNTRY[lc]) return EN_TO_RU_COUNTRY[lc]; // exact
  for (const [en, ru] of Object.entries(EN_TO_RU_COUNTRY)) { // partial
    if (lc.includes(en)) return ru;
  }
  return t; // unknown — return as-is
}

/**
 * Split "City, Country" or "Country, City" text into {country, city}.
 * country is always normalized to Russian.
 */
function parseLocation(text) {
  if (!text) return { country: null, city: null };
  // Strip leading "г.", "г " city prefixes
  const cleaned = text.replace(/^г\.?\s*/u, '').trim();
  const parts = cleaned.split(/[,;]/).map(p => p.replace(/^г\.?\s*/u, '').trim()).filter(Boolean);

  if (parts.length === 0) return { country: null, city: null };

  if (parts.length === 1) {
    const ru = normalizeCountryToRu(parts[0]);
    return RU_KNOWN_COUNTRIES.has(ru)
      ? { country: ru, city: null }
      : { country: null, city: parts[0] };
  }

  // Two or more parts — detect which is country
  const first  = normalizeCountryToRu(parts[0]);
  const second = normalizeCountryToRu(parts[1]);
  if (RU_KNOWN_COUNTRIES.has(first))  return { country: first,  city: parts[1] };
  if (RU_KNOWN_COUNTRIES.has(second)) return { country: second, city: parts[0] };
  // Fallback: assume "City, Country"
  return { country: normalizeCountryToRu(parts[1]), city: parts[0] };
}

// ─── Salary normalization ─────────────────────────────────────────────────────

const CURRENCY_PATTERNS = [
  [/€|EUR|евро/i,  'EUR'],
  [/\$|USD/i,      'USD'],
  [/£|GBP/i,       'GBP'],
  [/zł|PLN|злот/i, 'PLN'],
  [/грн|UAH|гривн/i, 'UAH'],
  [/₽|RUB|руб/i,  'RUB'],
  [/SEK/i, 'SEK'],
  [/NOK/i, 'NOK'],
  [/DKK/i, 'DKK'],
  [/CZK/i, 'CZK'],
];

const PERIOD_PATTERNS = [
  [/\/h(?:r|our)?\b|в\s*час/i,                 'hour'],
  [/\/d(?:ay)?\b|в\s*(?:день|сутки|смену)/i,   'day'],
  [/\/mo(?:nth)?\b|в\s*месяц|per\s*month/i,    'month'],
  [/\/y(?:r|ear)?\b|в\s*год|per\s*year/i,      'year'],
];

function parseSalary(text) {
  if (!text) return { from: null, to: null, currency: null, period: null };

  let currency = null;
  for (const [pat, code] of CURRENCY_PATTERNS) {
    if (pat.test(text)) { currency = code; break; }
  }

  let period = null;
  for (const [pat, p] of PERIOD_PATTERNS) {
    if (pat.test(text)) { period = p; break; }
  }

  // Strip non-numeric noise; keep digits, spaces, decimal separators, range dashes
  const numStr = text
    .replace(/[€$£₽]/g, ' ')
    .replace(/[a-zA-Zа-яёА-ЯЁ]/g, ' ')
    .replace(/[,]/g, '')                        // remove thousands commas
    .replace(/(\d{1,3})\s(\d{3})\b/g, '$1$2')  // join space-separated thousands: "1 500" → "1500"
    .replace(/\s+/g, ' ')
    .trim();

  let from = null;
  let to   = null;

  // Range: "2000 - 3000" or "2000–3000"
  const rangeMatch = numStr.match(/(\d+(?:\.\d+)?)\s*[-–—]\s*(\d+(?:\.\d+)?)/);
  if (rangeMatch) {
    const a = parseFloat(rangeMatch[1]);
    const b = parseFloat(rangeMatch[2]);
    if (a > 0 && b > 0) {
      from = Math.min(a, b);
      to   = a !== b ? Math.max(a, b) : null;
    }
  }

  // "от N" / "from N" / "min N" in original text
  if (from === null) {
    const m = text.match(/(?:от|from|min\.?(?:imum)?|начиная\s+с)\s*([\d\s]+)/i);
    if (m) { const n = Number(m[1].replace(/\s/g, '')); if (n > 0) from = n; }
  }

  // "до N" / "up to N" / "max N" in original text
  if (to === null) {
    const m = text.match(/(?:до|up\s+to|max\.?(?:imum)?)\s*([\d\s]+)/i);
    if (m) { const n = Number(m[1].replace(/\s/g, '')); if (n > 0) to = n; }
  }

  // Single number fallback — require ≥ 3 digits (filters out "18" for hourly handled below)
  if (from === null && to === null) {
    const nums = numStr.match(/\b(\d{3,})\b/g);
    if (nums) { const n = Number(nums[0]); if (n > 0) from = n; }
    // Hourly rates may be 2-digit; accept if period is hour
    if (from === null && period === 'hour') {
      const n2 = numStr.match(/\b(\d{2,})\b/g);
      if (n2) { const n = Number(n2[0]); if (n > 0) from = n; }
    }
  }

  if (from !== null && from <= 0) from = null;
  if (to   !== null && to   <= 0) to   = null;
  if (from !== null && to !== null && to < from) to = null;

  return { from: from || null, to: to || null, currency, period };
}

// ─── Experience normalization ─────────────────────────────────────────────────

function parseExperience(text) {
  if (!text) return null;
  const t = text.toLowerCase().replace(/[–—]/g, '-');

  if (/без\s*опыта|no\s+exp|не\s+треб|not\s+required|experience\s+not|стаж\s+не|freshmen/.test(t))
    return 'no_experience';
  if (/(?:до|less\s+than|менее|меньше|under)\s*1|0\s*-\s*1\s*(?:год|лет|year)|6\s*мес/.test(t))
    return 'lt1';
  if (/1\s*-\s*3|от\s*1\s+до\s*3|1\s+to\s+3/.test(t))
    return '1_3';
  if (/3\s*-\s*5|от\s*3\s+до\s*5|3\s+to\s+5/.test(t))
    return '3_5';
  if (/(?:более|от|свыше|over|more\s+than|min(?:imum)?\s+)\s*5|5\s*\+|\+5/.test(t))
    return '5_plus';

  // Numeric fallback — extract "N лет" / "N years"
  const m = t.match(/(\d+)\s*(?:-\s*(\d+))?\s*(?:лет|год|year|yr)/);
  if (m) {
    const lo = Number(m[1]);
    const hi = m[2] ? Number(m[2]) : lo;
    if (lo === 0 && hi === 0) return 'no_experience';
    if (hi <= 1)  return 'lt1';
    if (hi <= 3)  return '1_3';
    if (hi <= 5)  return '3_5';
    return '5_plus';
  }

  return null;
}

// ─── Gender normalization ─────────────────────────────────────────────────────

function parseGender(text) {
  if (!text) return null;
  const t = text.toLowerCase();
  if (/\b(?:мужчин|мужск|male\b|men\b|man\b)/.test(t))   return 'male';
  if (/\b(?:женщин|женск|female|women|woman)/.test(t)) return 'female';
  if (/не\s+важно|any|not.specified/i.test(t)) return 'not_specified';
  return null;
}

// ─── Age range normalization ──────────────────────────────────────────────────

function parseAgeRange(text) {
  if (!text) return { from: null, to: null };
  const t = text.replace(/[–—]/g, '-');

  const range = t.match(/(\d{2})\s*-\s*(\d{2})/);
  if (range) {
    const a = Number(range[1]), b = Number(range[2]);
    if (a >= 14 && b <= 80) return { from: Math.min(a, b), to: Math.max(a, b) };
  }

  const single = t.match(/(?:от|from|не\s+менее|старше)?\s*(\d{2})\s*(?:\+|лет|год|year)?/i);
  if (single) {
    const n = Number(single[1]);
    if (n >= 14 && n <= 80) return { from: n, to: null };
  }

  return { from: null, to: null };
}

// ─── Driving licenses normalization ──────────────────────────────────────────

const VALID_LICENSE_CATS = new Set(['A', 'B', 'C', 'D', 'E', 'BE', 'CE']);

function parseDrivingLicenses(text) {
  if (!text) return [];
  const seen = new Set();
  const result = [];
  const matches = text.match(/\b(?:BE|CE|[ABCDE])\b/g) ?? [];
  for (const m of matches) {
    const k = m.toUpperCase();
    if (VALID_LICENSE_CATS.has(k) && !seen.has(k)) { seen.add(k); result.push(k); }
  }
  return result;
}

// ─── Boolean from free text ───────────────────────────────────────────────────

/**
 * Return true if text confirms a feature is provided,
 * false if it explicitly says it is NOT, null if text is empty.
 */
function detectBoolean(text) {
  if (!text) return null;
  if (/не\s+предоставл|не\s+предусмотр|no\s+|not\s+provided|without/i.test(text)) return false;
  return true;
}

// ─── Language level normalization ─────────────────────────────────────────────

const LANG_LEVEL_MAP = {
  'native':           'native', 'родной':       'native', 'носитель':    'native',
  'c2':               'C2',     'advanced':     'C2',     'свободно':    'C2',
  'fluent':           'C2',     'свободный':    'C2',     'профессиональный': 'C2',
  'c1':               'C1',     'upper-advanced': 'C1',
  'b2':               'B2',     'upper-intermediate': 'B2', 'разговорный': 'B2',
  'conversational':   'B2',
  'b1':               'B1',     'intermediate': 'B1',     'средний':     'B1',
  'a2':               'A2',     'elementary':   'A2',     'базовый':     'A2',
  'basic':            'A2',     'pre-intermediate': 'A2', 'ниже среднего': 'A2',
  'a1':               'A1',     'beginner':     'A1',     'начинающий':  'A1',
};

function normalizeLangLevel(text) {
  if (!text) return null;
  const lc = text.toLowerCase().trim();
  if (LANG_LEVEL_MAP[lc]) return LANG_LEVEL_MAP[lc];
  for (const [k, v] of Object.entries(LANG_LEVEL_MAP)) {
    if (lc.includes(k)) return v;
  }
  const cef = lc.match(/\b(a1|a2|b1|b2|c1|c2)\b/i);
  if (cef) return cef[1].toUpperCase();
  return null;
}

// ─── OpenAI call with retry ───────────────────────────────────────────────────

async function callOpenAI(systemPrompt, userContent, { maxRetries = 1 } = {}) {
  const client = getClient();
  let lastErr;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      const completion = await client.chat.completions.create({
        model: 'gpt-4o-mini',
        temperature: 0,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user',   content: userContent  },
        ],
      });
      const raw = completion.choices[0]?.message?.content ?? '{}';
      return JSON.parse(raw);
    } catch (err) {
      lastErr = err;
      if (err instanceof SyntaxError && attempt < maxRetries) continue; // retry on bad JSON
      throw err;
    }
  }
  throw lastErr || new Error('AI parsing failed');
}

// ═══════════════════════════════════════════════════════════════════════════════
// VACANCY — STAGE 1 PROMPT
// ═══════════════════════════════════════════════════════════════════════════════

const VACANCY_STAGE1_PROMPT = `You are a semantic extractor for job postings.
Extract raw meaning from the text. Do NOT convert to codes or enums.
Return ONLY valid JSON. No markdown. No explanations.

Rules:
- Extract exactly what is written. Never invent missing information.
- Use null for absent fields. Use [] for absent arrays.
- responsibilities = what the employee will DO (duties, tasks).
- requirements    = what the candidate must HAVE (skills, documents, experience, traits).
- Do not mix responsibilities with requirements.
- Do not repeat in description what is already in responsibilities/requirements.
- description = brief company or role context only, max 3 sentences.

Required output:
{
  "job_title": "job title as written | null",
  "category_text": "job category or industry | null",
  "location_text": "city and/or country as written, e.g. 'Таллинн, Эстония' | null",
  "salary_text": "salary exactly as written, e.g. '2000–3000 EUR/month' or 'от 1800 EUR' | null",
  "schedule_text": "work schedule as written | null",
  "employment_type_texts": ["employment types exactly as written"],
  "gender_text": "gender requirement as written | null",
  "age_text": "age requirement as written, e.g. '25–45 лет' | null",
  "vacancies_count_text": "number of open positions as written | null",
  "citizenship_text": "citizenship requirement as written | null",
  "experience_text": "experience requirement as written, e.g. 'от 1 года' | null",
  "driving_license_text": "license categories as written, e.g. 'категория B, C' | null",
  "car_required_text": "text about personal car requirement | null",
  "language_texts": ["language requirements exactly as written"],
  "responsibilities": ["one duty per item — what the employee will do"],
  "requirements": ["one requirement per item — what candidate must have"],
  "description": "brief company or role context, max 3 sentences | null",
  "benefit_housing_text": "text confirming housing is provided | null",
  "benefit_transport_text": "text confirming transport/commute is provided | null",
  "benefit_teens_text": "text indicating teens or students are welcome | null",
  "benefit_disabled_text": "text indicating disabled persons are welcome | null",
  "urgent_text": "text indicating this vacancy is urgent | null"
}`;

// ─── Vacancy Stage 2: deterministic normalization ─────────────────────────────

function normalizeVacancyFromSemantic(sem, sourceLang) {
  if (!sem || typeof sem !== 'object') return {};

  const salary = parseSalary(clean(sem.salary_text));
  const age    = parseAgeRange(clean(sem.age_text));
  const loc    = parseLocation(clean(sem.location_text));

  return {
    source_language: sourceLang,

    title:    clean(sem.job_title),
    category: clean(sem.category_text),
    country:  loc.country,
    city:     loc.city,

    salary_from:   salary.from,
    salary_to:     salary.to,
    currency:      salary.currency,
    salary_period: salary.period,

    work_schedule:   clean(sem.schedule_text),
    employment_tags: cleanArray(sem.employment_type_texts),

    gender:              parseGender(clean(sem.gender_text)),
    vacancies_count:     toNum(sem.vacancies_count_text),
    citizenship:         clean(sem.citizenship_text),
    experience_required: parseExperience(clean(sem.experience_text)),

    age_from: age.from,
    age_to:   age.to,

    driving_licenses: parseDrivingLicenses(clean(sem.driving_license_text)),
    car_required:     detectBoolean(clean(sem.car_required_text)),
    languages:        cleanArray(sem.language_texts),

    responsibilities: cleanArray(sem.responsibilities),
    requirements:     cleanArray(sem.requirements),
    description:      trimToLength(clean(sem.description), 600),

    housing_provided:   detectBoolean(clean(sem.benefit_housing_text)),
    transport_provided: detectBoolean(clean(sem.benefit_transport_text)),
    for_teens:          detectBoolean(clean(sem.benefit_teens_text)),
    for_disabled:       detectBoolean(clean(sem.benefit_disabled_text)),
    urgent_vacancy:     detectBoolean(clean(sem.urgent_text)),
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
// CV — STAGE 1 PROMPT
// ═══════════════════════════════════════════════════════════════════════════════

const CV_STAGE1_PROMPT = `You are a semantic extractor for resumes and CVs.
Extract raw meaning from the text. Do NOT convert to codes or enums.
Return ONLY valid JSON. No markdown. No explanations.

Critical rules:
- NEVER confuse work experience with desired job preferences.
  Work experience = jobs the person actually held (past or current).
  Job preferences = what the person is looking for now.
- NEVER invent dates. Use null if a date is absent or unclear.
- is_current_text: copy the exact phrase that says they are still working there
  (e.g. 'по настоящее время', 'н.в.', 'current', 'present'). Use null if not found.
- Extract language levels literally (native, B2, разговорный, базовый, etc.).
- Keep description per job concise — max 2 sentences.

Required output:
{
  "source_language": "ISO-639-1: ru | en | et | uk | null",
  "job_title": "professional headline or desired position | null",
  "summary_text": "candidate's key strengths in their own words, max 4 sentences | null",
  "experience": [
    {
      "position": "job title | null",
      "company": "company name | null",
      "location_text": "city and/or country as written | null",
      "description": "what they did, max 2 sentences | null",
      "start_date_text": "start date as written, e.g. 'март 2019' or '03.2019' | null",
      "end_date_text": "end date as written, or null if still working | null",
      "is_current_text": "phrase indicating still employed here | null"
    }
  ],
  "education": [
    {
      "school": "institution name | null",
      "specialization": "degree or field of study | null",
      "location_text": "city / country | null",
      "start_date_text": "start as written | null",
      "end_date_text": "end as written | null",
      "is_current_text": "phrase indicating still studying | null"
    }
  ],
  "language_texts": [
    {
      "name": "language name | null",
      "level_text": "level as written, e.g. 'B2', 'fluent', 'базовый' | null"
    }
  ],
  "computer_skills_text": "raw skills list or free text | null",
  "driving_license_text": "categories or yes/no text as written | null",
  "desired_category_text": "desired job category | null",
  "desired_position_text": "desired job title | null",
  "desired_location_text": "desired city / country | null",
  "desired_employment_type_text": "desired employment type | null"
}`;

// ─── CV Stage 2: deterministic normalization ──────────────────────────────────

function normalizeCVFromSemantic(sem, sourceLang) {
  if (!sem || typeof sem !== 'object') return {};

  const experience = Array.isArray(sem.experience)
    ? sem.experience
        .map((e) => {
          const isCurrent = !!clean(e?.is_current_text);
          const loc = parseLocation(clean(e?.location_text));
          return {
            position:    clean(e?.position),
            company:     clean(e?.company),
            country:     loc.country,
            description: trimToLength(clean(e?.description), 300),
            start_date:  cleanDate(e?.start_date_text),
            end_date:    isCurrent ? null : cleanDate(e?.end_date_text),
            is_current:  isCurrent,
          };
        })
        .filter((e) => e.position || e.company)
    : [];

  const education = Array.isArray(sem.education)
    ? sem.education
        .map((e) => {
          const isCurrent = !!clean(e?.is_current_text);
          const loc = parseLocation(clean(e?.location_text));
          return {
            school:         clean(e?.school),
            specialization: clean(e?.specialization),
            country:        loc.country,
            start_date:     cleanDate(e?.start_date_text),
            end_date:       isCurrent ? null : cleanDate(e?.end_date_text),
            is_current:     isCurrent,
          };
        })
        .filter((e) => e.school)
    : [];

  const languages = Array.isArray(sem.language_texts)
    ? sem.language_texts
        .map((l) => ({
          name:  clean(l?.name),
          level: normalizeLangLevel(clean(l?.level_text)),
        }))
        .filter((l) => l.name)
    : [];

  // Desired location
  const desiredLoc = parseLocation(clean(sem.desired_location_text));

  // Driving license: prefer boolean detection, fall back to checking if categories mentioned
  const dlText = clean(sem.driving_license_text);
  let drivingLicense = detectBoolean(dlText);
  if (drivingLicense === null && parseDrivingLicenses(dlText).length > 0) drivingLicense = true;

  return {
    source_language: sourceLang ?? clean(sem.source_language),

    title:   clean(sem.job_title),
    summary: trimToLength(clean(sem.summary_text), 800),

    experience,
    education,
    languages,

    computer_skills: clean(sem.computer_skills_text),
    driving_license: drivingLicense,

    job_preferences: {
      category:        clean(sem.desired_category_text),
      position:        clean(sem.desired_position_text),
      country:         desiredLoc.country,
      city:            desiredLoc.city,
      employment_type: clean(sem.desired_employment_type_text),
    },
  };
}

// ─── Public API ───────────────────────────────────────────────────────────────

/**
 * Parse raw vacancy/job posting text → normalised structured object.
 * @param {string} text
 * @returns {Promise<object>}
 */
async function parseVacancyText(text) {
  const sourceLang = detectLanguage(text);
  const semantic   = await callOpenAI(
    VACANCY_STAGE1_PROMPT,
    `Extract all available information from this job posting:\n\n${text}`,
    { maxRetries: 1 },
  );
  return normalizeVacancyFromSemantic(semantic, sourceLang);
}

/**
 * Parse raw CV/resume text → normalised structured object.
 * @param {string} text
 * @returns {Promise<object>}
 */
async function parseCVText(text) {
  const sourceLang = detectLanguage(text);
  const semantic   = await callOpenAI(
    CV_STAGE1_PROMPT,
    `Extract all available information from this CV/resume:\n\n${text}`,
    { maxRetries: 1 },
  );
  return normalizeCVFromSemantic(semantic, sourceLang);
}

module.exports = { parseVacancyText, parseCVText };

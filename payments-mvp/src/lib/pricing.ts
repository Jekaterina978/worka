import type { Product } from '../types';

export const CREDIT_PACKAGES: Product[] = [
  { id: 'credits_1', type: 'credits', title: '1 контакт', titleEn: '1 contact', amountEur: 3.49, quantity: 1 },
  { id: 'credits_5', type: 'credits', title: '5 контактов', titleEn: '5 contacts', amountEur: 14.99, quantity: 5 },
  { id: 'credits_20', type: 'credits', title: '20 контактов', titleEn: '20 contacts', amountEur: 49.99, quantity: 20 },
];

export const EMPLOYER_VERIFICATION: Product = {
  id: 'employer_verification',
  type: 'employer_verification',
  title: 'Верификация работодателя',
  titleEn: 'Employer verification',
  amountEur: 19,
};

export const JOB_PROMOTIONS: Product[] = [
  {
    id: 'highlight_job_7d',
    type: 'job_promotion',
    title: 'Выделение вакансии (7 дней)',
    titleEn: 'Highlight job (7 days)',
    amountEur: 6.99,
    metadata: { kind: 'highlight_job', durationDays: 7 },
  },
  {
    id: 'promotion_urgent',
    type: 'job_promotion',
    title: 'Срочная вакансия (7 дней)',
    titleEn: 'Urgent badge (7 days)',
    amountEur: 7.99,
    metadata: { kind: 'urgent', durationDays: 7 },
  },
  {
    id: 'promotion_bump',
    type: 'job_promotion',
    title: 'Обновление в ленте (72ч)',
    titleEn: 'List bump (72h)',
    amountEur: 4.99,
    metadata: { kind: 'bump', durationHours: 72 },
  },
  {
    id: 'promotion_show_employer_contacts',
    type: 'job_promotion',
    title: 'Показать контакты работодателя',
    titleEn: 'Show employer contacts',
    amountEur: 50.0,
    metadata: { kind: 'show_employer_contacts' },
  },
];

export const PLANS: Product[] = [
  {
    id: 'basic',
    type: 'subscription',
    title: 'Basic',
    titleEn: 'Basic',
    amountEur: 39,
    metadata: { jobs: 5, creditsMonthly: 15, bumpsMonthly: 2 },
  },
  {
    id: 'pro',
    type: 'subscription',
    title: 'Pro',
    titleEn: 'Pro',
    amountEur: 79,
    metadata: { jobs: 15, creditsMonthly: 50, bumpsMonthly: 5, urgentMonthly: 3, cvDatabase: true },
  },
  {
    id: 'agency',
    type: 'subscription',
    title: 'Agency',
    titleEn: 'Agency',
    amountEur: 149,
    metadata: { jobs: 'unlimited', creditsMonthly: 150, priority: true },
  },
];

export const JOB_SEEKER_BOOSTS: Product[] = [
  {
    id: 'cv_bump_48h',
    type: 'job_seeker_boost',
    title: 'Поднять CV (48ч)',
    titleEn: 'Bump CV (48h)',
    amountEur: 1.99,
    metadata: { kind: 'cv_bump', durationHours: 48 },
  },
  {
    id: 'cv_highlight_7d',
    type: 'job_seeker_boost',
    title: 'Выделить CV (7 дней)',
    titleEn: 'Highlight CV (7 days)',
    amountEur: 2.49,
    metadata: { kind: 'cv_highlight', durationDays: 7 },
  },
  {
    id: 'jobseeker_verified',
    type: 'job_seeker_boost',
    title: 'Подтвержденный профиль',
    titleEn: 'Verified profile',
    amountEur: 4.99,
    metadata: { kind: 'profile_verified' },
  },
];

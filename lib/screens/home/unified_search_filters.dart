import '../search/models/search_filters.dart';
import '../candidates/widgets/candidate_filters_screen.dart';
import '../employer/search/models/candidate_filters.dart';

enum SearchMode { vacancies, candidates }

class UnifiedSearchFilters {
  final SearchMode mode;
  final SearchFilters vacancy;
  final CandidateFilters candidate;

  const UnifiedSearchFilters({
    required this.mode,
    required this.vacancy,
    required this.candidate,
  });

  factory UnifiedSearchFilters.initial() => UnifiedSearchFilters(
    mode: SearchMode.vacancies,
    vacancy: SearchFilters.initial(),
    candidate: CandidateFilters.initial(),
  );

  UnifiedSearchFilters copyWith({
    SearchMode? mode,
    SearchFilters? vacancy,
    CandidateFilters? candidate,
  }) {
    return UnifiedSearchFilters(
      mode: mode ?? this.mode,
      vacancy: vacancy ?? this.vacancy,
      candidate: candidate ?? this.candidate,
    );
  }
}

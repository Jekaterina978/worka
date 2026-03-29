class FirestorePaths {
  static const cvs = 'cvs';
  static const cvsTest = 'cvs_test';
  static const candidates = cvs;
  static const jobs = 'jobs';
  static const jobsTest = 'jobs_test';
  static const vacancies = 'jobs';
  static const vacanciesTest = 'jobs_test';
  static const responses = 'responses';
  static const responsesTest = 'responses_test';
  static const applications = 'applications';
  static const jobOffers = 'jobOffers';
  static const offers = jobOffers;
  static const notifications = 'notifications';

  static String cvsCol({required bool testMode, bool authed = false}) {
    return testMode ? cvsTest : cvs;
  }

  static String jobsCol({required bool testMode, bool authed = false}) {
    return testMode ? jobsTest : jobs;
  }

  static String responsesCol({required bool testMode, bool authed = false}) {
    return testMode ? responsesTest : responses;
  }

  static String notificationsItemsCol(String userId) {
    return '$notifications/$userId/items';
  }

  static String userCvsCol(String userId) {
    return 'users/$userId/cvs';
  }

  static String userVacanciesCol(String userId) {
    return 'users/$userId/vacancies';
  }
}

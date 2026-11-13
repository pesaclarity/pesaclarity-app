/// Ask's words on screen, in one place.
abstract final class AskStrings {
  static const title = 'Ask';
  static const emptyTitle = 'Ask about your money';
  static String emptyBody(String space) =>
      'Answers come from your own records, on this phone. '
      'Asks stay in $space.';
  static const tryAsking = 'TRY ASKING';
  static const hideSuggestions = 'Hide suggestions';
  static const hint = 'Ask about your money';
  static String hintFor(String space) => 'Ask about $space';
  static const followUpHint = 'Ask a follow-up';
  static const send = 'Ask';
  static const askingAbout = 'Asking about';
  static String dropTag(String tag) => 'Stop asking about $tag';
  static const thinking = 'Looking at your records';
  static String seeAll(int n) => 'See all $n';
  static const seePayments = 'See the payments';
  static const openBusinessInsights = 'Open in Business insights';
  static String numbersAsOf(String date) => 'Numbers as of $date';
  static const update = 'Update';
  static const theseMightHelp = 'These might help:';
  static const andForWhen = 'And for when?';
  static const both = 'Both';
  static const bothDetail = 'Add them together';
  static const all = 'All of them';
  static const conversations = 'Conversations';
  static const newConversation = 'New conversation';
  static const searchConversations = 'Search conversations';
  static const today = 'TODAY';
  static const thisWeek = 'THIS WEEK';
  static const earlier = 'EARLIER';
  static const noConversations =
      'Conversations you have here show up in this list.';
  static const noMatches = 'No conversations match.';
  static const more = 'More';
  static const namedFromFirst = 'Named from your first question';
  static const rename = 'Rename';
  static const updateAll = 'Update all numbers';
  static const startNew = 'Start a new conversation';
  static const deleteConversation = 'Delete conversation';
  static const deleteConversationQuestion = 'Delete this conversation?';
  static const deleteAllQuestion = 'Delete all conversations?';
  static const deleteConversationBody =
      'This conversation goes from this phone.';
  static const settings = 'Ask settings';
  static const renameTitle = 'Rename conversation';
  static const save = 'Save';
  static const cancel = 'Cancel';
  static const showAsk = 'Show Ask';
  static const showAskDetail = 'A button on Home';
  static const saveConversations = 'Save conversations';
  static const saveConversationsDetail = 'On this phone, in each space';
  static const keepFor = 'Keep them for';
  static const keepForDetail = 'Older ones are removed';
  static const chartsInAnswers = 'Charts in answers';
  static const chartsDetail = 'When an answer has a trend';
  static const deleteAll = 'Delete all conversations';
  static String deleteAllDetail(String space) => 'In $space only';
  static String deleteAllBody(String space) =>
      'Every conversation and word Ask learned in $space goes from this '
      'phone.';
  static const settingsFootnote =
      'Conversations never leave the phone and are not in backups.';
  static const profileRow = 'Ask';
  static const profileRowDetail = 'Conversations and settings';
  static String askAbout(String what) => 'Ask about $what';
  static String askAboutThisMonth(String category) =>
      'Ask about ${category.toLowerCase()} this month';
  static const periodThisMonth = 'This month';
  static const periodLastMonth = 'Last month';
  static const periodThisWeek = 'This week';
  static const periodLast3Months = 'Last 3 months';
  static const periodThisYear = 'This year';

  static const keepForLabels = {
    'untilDeleted': 'Until I delete',
    'year': '1 year',
    'days90': '90 days',
    'days30': '30 days',
    'days7': '7 days',
  };
}

void main() {
  final testCases = [
    'setup-fitgirl-01.bin',
    'setup-fitgirl-selective-english.bin',
    'setup-fitgirl-optional-credits.bin',
    'setup-fitgirl-optional-language-french.bin', // User specific request
    'Updated_Setup_v1.bin',
    'QuickFix.exe',
    'fg-02.bin',
    'setup-fitgirl-optional-bonus-ost.bin',
  ];

  print('Running Categorization Logic Test...\n');

  final updatedRegex = RegExp(r'(update|patch|fix)', caseSensitive: false);
  final langRegex = RegExp(
    r'(selective|language|german|french|spanish|italian|russian|portuguese|brazilian|japanese|chinese|korean|polish|traditional|simplified|arab)',
    caseSensitive: false,
  );

  for (var name in testCases) {
    final lowerName = name.toLowerCase();

    bool isUpdated =
        updatedRegex.hasMatch(lowerName) &&
        !lowerName.contains('setup-fitgirl');
    bool isLanguage = langRegex.hasMatch(lowerName);
    bool isOptional = lowerName.contains('optional');

    String tag;
    if (isUpdated) {
      tag = 'UPDATE';
    } else if (isLanguage) {
      tag = 'LANG';
    } else if (isOptional) {
      tag = 'OPT';
    } else {
      tag = 'REQ'; // Core
    }

    print('File: $name -> Tag: $tag');
  }
}

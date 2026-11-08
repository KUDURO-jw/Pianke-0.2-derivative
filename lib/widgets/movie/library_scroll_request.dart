import 'package:flutter/foundation.dart';

/// A command shared by the dock and library, without rebuilding the page.
class LibraryScrollRequest extends ChangeNotifier {
  void scrollToTop() => notifyListeners();
}

import 'package:flutter/widgets.dart';

import '../features/home/home_screen.dart';
import '../shared/theme/app_theme.dart';

/// Root application. Material is deliberately not used anywhere -- the whole
/// interface is built from the game's own angular design system.
class KanbanSlicerApp extends StatelessWidget {
  const KanbanSlicerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      title: 'Kanban Slicer',
      color: K.bgDeep,
      debugShowCheckedModeBanner: false,
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
          FadeRoute<T>(builder: builder, settings: settings),
      builder: (context, child) => DefaultTextStyle(
        style: K.label(13, color: K.white),
        child: MediaQuery.withNoTextScaling(
          child: ColoredBox(color: K.bgDeep, child: child ?? const SizedBox()),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

/// Cross-fade + slight scale transition used for every screen change.
class FadeRoute<T> extends PageRoute<T> {
  FadeRoute({required this.builder, super.settings});

  final WidgetBuilder builder;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 240);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
        child: child,
      ),
    );
  }
}

/// Pushes a screen with the app's standard transition.
Future<T?> pushScreen<T>(BuildContext context, Widget screen) =>
    Navigator.of(context).push<T>(FadeRoute<T>(builder: (_) => screen));

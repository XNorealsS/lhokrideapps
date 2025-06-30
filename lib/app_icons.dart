import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/widgets.dart';

class AppIcons {
  static Widget becak({double? size, Color? color}) {
    return SvgPicture.asset(
      'assets/icons/becak.svg',
      width: size,
      height: size,
      color: color,
    );
  }

  static Widget lhlogo({double? size, Color? color}) {
    return SvgPicture.asset(
      'assets/icons/iconu.svg',
      width: size,
      height: size,
      color: color,
    );
  }

static Widget lhlagos({Color? color}) {
  return SvgPicture.asset(
    'assets/icons/iconu.svg',
    fit: BoxFit.contain, // Penting untuk menyesuaikan ukuran parent
    color: color,
  );
}

  static Widget lhmaskoot({double? size, Color? color}) {
    return SvgPicture.asset(
      'assets/icons/maskot_lh.svg',
      width: size,
      height: size,
      color: color,
    );
  }

    static Widget orange_logo({double size = 24}) {
    return Image.asset(
      'assets/icons/logo.png',
      width: size,
      height: size,
    );
  }
}

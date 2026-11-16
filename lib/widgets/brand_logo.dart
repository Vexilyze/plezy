import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../utils/build_identity.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => isVexilyzeBuild
      ? SvgPicture.asset('assets/vexilyze.svg', width: size, height: size, semanticsLabel: appDisplayName)
      : Image.asset('assets/plezy.png', width: size, height: size);
}

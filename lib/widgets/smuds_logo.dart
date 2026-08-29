import 'package:flutter/material.dart';

/// 세명대학교 재난안전학과 로고.
///
/// 원본이 가로로 매우 긴 비율(약 3.6:1)이라 높이를 기준으로 크기를 잡는다.
class SmudsLogo extends StatelessWidget {
  const SmudsLogo({super.key, this.height = 34});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '세명대학교 재난안전학과',
      child: Image.asset(
        'assets/images/smuds_logo.png',
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

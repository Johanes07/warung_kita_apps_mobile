import 'package:flutter/material.dart';
 
import '../size_config.dart';
 
class DefaultButtonCustomeColor extends StatelessWidget {
  const DefaultButtonCustomeColor({
    super.key,
    this.text,
    this.color,
    this.press,
  });
  final String? text;
  final Color? color;
  final Function? press;
 
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: getProportionateScreenHeight(56),
      child: TextButton(
        style: TextButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          foregroundColor: Colors.white, // ✅ ganti primary -> foregroundColor
          backgroundColor: color,
        ),
        onPressed: press as void Function()?,
        child: Text(
          text!,
          style: TextStyle(
            fontSize: getProportionateScreenWidth(18),
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:warung_kita/utils/constants.dart';


ThemeData theme() {
  return ThemeData(
    scaffoldBackgroundColor: Colors.white,
    fontFamily: "Muli",
    appBarTheme: appBarTheme(),
    textTheme: textTheme(),
    inputDecorationTheme: inputDecorationTheme(),
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
}

InputDecorationTheme inputDecorationTheme() {
  OutlineInputBorder outlineInputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(28),
    borderSide: const BorderSide(color: kTextColor),
    gapPadding: 10,
  );
  return InputDecorationTheme(
    floatingLabelBehavior: FloatingLabelBehavior.always,
    contentPadding: const EdgeInsets.symmetric(horizontal: 42, vertical: 20),
    enabledBorder: outlineInputBorder,
    focusedBorder: outlineInputBorder,
    border: outlineInputBorder,
  );
}

TextTheme textTheme() {
  return const TextTheme(
    bodyLarge: TextStyle(color: kTextColor),   // dulu bodyText1
    bodyMedium: TextStyle(color: kTextColor),  // dulu bodyText2
  );
}

AppBarTheme appBarTheme() {
  return const AppBarTheme(
    backgroundColor: Colors.white,
    elevation: 0,
    // brightness sudah deprecated, pakai systemOverlayStyle
    systemOverlayStyle: Brightness.light == Brightness.dark
        ? null
        : null, // bisa atur sesuai kebutuhan
    iconTheme: IconThemeData(color: Colors.black),
    titleTextStyle: TextStyle(                // ganti headline6
      color: Color(0XFF8B8B8B),
      fontSize: 18,
    ),
  );
}

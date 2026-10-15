import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color primarySeedColor = Colors.blue;

final TextTheme appTextTheme = TextTheme(
  displayLarge: GoogleFonts.pacifico(fontSize: 57, fontWeight: FontWeight.bold),
  titleLarge: GoogleFonts.lato(fontSize: 22, fontWeight: FontWeight.w500),
  bodyMedium: GoogleFonts.lato(fontSize: 14),
);

final ThemeData lightTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: primarySeedColor,
    brightness: Brightness.light,
  ),
  textTheme: appTextTheme,
  appBarTheme: AppBarTheme(
    backgroundColor: primarySeedColor,
    foregroundColor: Colors.white,
    titleTextStyle: GoogleFonts.lato(fontSize: 24, fontWeight: FontWeight.bold),
  ),
);

final ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: primarySeedColor,
    brightness: Brightness.dark,
  ),
  textTheme: appTextTheme,
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.grey[900],
    foregroundColor: Colors.white,
    titleTextStyle: GoogleFonts.lato(fontSize: 24, fontWeight: FontWeight.bold),
  ),
);

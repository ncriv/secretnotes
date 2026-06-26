import 'package:flutter/material.dart';

const List<Color> noteColors = [
  Color(0xFF5C6BC0), // Indigo
  Color(0xFF26A69A), // Teal
  Color(0xFFEF5350), // Red
  Color(0xFFAB47BC), // Purple
  Color(0xFF42A5F5), // Blue
  Color(0xFFFFA726), // Orange
  Color(0xFF66BB6A), // Green
  Color(0xFFEC407A), // Pink
  Color(0xFF8D6E63), // Brown
  Color(0xFF78909C), // Blue Grey
];

Color getNoteColor(int colorIndex) =>
    noteColors[colorIndex % noteColors.length];

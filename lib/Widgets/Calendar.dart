import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class Calendar extends StatefulWidget {
  const Calendar({super.key});

  @override
  State<Calendar> createState() => _CalendarState();
}

class _CalendarState extends State<Calendar> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final days = _getNext14Days();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Next 14 Days',
            style: TextStyle(
              color: Colors.black54,
              fontSize: 24,
              fontFamily: 'Poppins',
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 70,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(14, (index) {
                  final dayData = days[index];
                  return GestureDetector(
                    onTap: () => setState(() {
                      _selectedIndex = _selectedIndex == index ? null : index;
                    }),
                    child: Container(
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _selectedIndex == index
                            ? Colors.grey[300]
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Text(
                            dayData['date']!,
                            style: TextStyle(
                              fontSize: 18,
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.bold,
                              color: _selectedIndex == index
                                  ? Colors.black
                                  : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dayData['day']!,
                            style: TextStyle(
                              fontSize: 16,
                              fontFamily: 'Poppins',
                              color: _selectedIndex == index
                                  ? Colors.black54
                                  : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, String>> _getNext14Days() {
    DateTime today = DateTime.now();
    return List.generate(14, (i) {
      DateTime day = today.add(Duration(days: i));
      return {
        'day': DateFormat('EEE').format(day),
        'date': DateFormat('d').format(day)
      };
    });
  }
}
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

//TODO : RE DISIGEN THE CALENDAR PAGE FOR BETTER UX

class Calendar extends StatefulWidget {
  const Calendar({super.key});

  @override
  State<Calendar> createState() => CalendarState();
}

class CalendarState extends State<Calendar> {
  int? selectedIndex = 0; // Initialize with first date selected

  @override
  void initState() {
    super.initState();
    selectedIndex = 0; // first date is selected on load
  }

  @override
  Widget build(BuildContext context) {
    final days = getNext14Days();

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
          //TODO: BETTER WAY TO DISPLAY THE MONTHS
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
                      if (index == 0) {
                        // Keep first date always selected
                        selectedIndex = 0;
                      } else {
                        selectedIndex = selectedIndex == index ? null : index;
                      }
                    }),
                    child: Container(
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: selectedIndex == index
                            ? Colors.grey[300]
                            : (index == 0 ? Colors.grey[300] : Colors.transparent),
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
                              color: selectedIndex == index
                                  ? Colors.black
                                  : (index == 0 ? Colors.black : Colors.black87),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dayData['day']!,
                            style: TextStyle(
                              fontSize: 16,
                              fontFamily: 'Poppins',
                              color: selectedIndex == index
                                  ? Colors.black54
                                  : (index == 0 ? Colors.black54 : Colors.black54),
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

  List<Map<String, String>> getNext14Days() {
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
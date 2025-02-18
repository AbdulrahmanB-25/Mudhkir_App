import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mudhkir_app/Widgets/Calendar.dart';
import 'add_medicine.dart'; // Make sure to import your Add_Medicine class

class Cabinet extends StatelessWidget {
  const Cabinet({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: appBar(),
      body: const Calendar(),
      // Add floating action button For adding Medicine
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const Add_Medicine()),
          );
        },
        backgroundColor: Colors.green, // Match your app's theme
        child: const Icon(Icons.add, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }

  AppBar appBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0.0,
      leading: GestureDetector(
        onTap: () {},
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: SvgPicture.asset(
            'assets/icons/back-svgrepo-com.svg',
            height: 30,
            width: 50,
          ),
        ),
      ),
      flexibleSpace: const Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: EdgeInsets.only(left: 45, bottom: 0.1),
          child: Text(
            'Your Drug Cabinet',
            style: TextStyle(
              color: Colors.black54,
              fontSize: 35,
              fontFamily: 'Poppins',
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      toolbarHeight: 105,
    );
  }
}
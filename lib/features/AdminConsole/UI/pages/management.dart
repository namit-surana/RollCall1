import 'package:fluent_ui/fluent_ui.dart';
import 'package:team_dart_knights_sih/features/AdminConsole/UI/widgets/management_card.dart';

import '../../../../core/constants.dart';

class AddUsers extends StatefulWidget {
  const AddUsers({Key? key}) : super(key: key);

  @override
  State<AddUsers> createState() => _AddUsersState();
}

class _AddUsersState extends State<AddUsers> {
  final List<List<String>> addList = [
    [
      'User',
      'User are the main interactors for the system.',
      '$commonPath/user.png'
    ],
    [
      'Teacher',
      'Teachers are the main interactors for the system.',
      '$commonPath/teacher.png'
    ],
    [
      'Class Room',
      'User are the main interactors for the system.',
      '$commonPath/myClassRoom.png'
    ],
    [
      'Groups',
      'User are the main interactors for the system.',
      '$commonPath/box.png'
    ],
    [
      'Students',
      'Teachers are the main interactors for the system.',
      '$commonPath/students.png'
    ],
    [
      'Attendance',
      'User are the main interactors for the system.',
      '$commonPath/attendance.png'
    ],
  ];
  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Management",
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 22,
                fontFamily: 'Poppins',
                color: Colors.black),
          ),
          const SizedBox(
            height: 20,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(
              3,
              (index) => AddUserCard(
                  addText: addList[index][0],
                  content: addList[index][1],
                  imagePath: addList[index][2],
                  index: index,),
            ),
          ),
          const SizedBox(
            height: 20,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(
              3,
              (index) => AddUserCard(
                  addText: addList[index + 3][0],
                  content: addList[index + 3][1],
                  imagePath: addList[index + 3][2],
                  index: index,),
            ),
          )
        ],
      ),
    );
  }
}
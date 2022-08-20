// import 'dar:ffi';

import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:bloc/bloc.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:team_dart_knights_sih/core/location_service.dart';
import 'package:team_dart_knights_sih/features/AdminConsole/Backend/aws_api_client.dart';
import 'package:team_dart_knights_sih/features/TeacherConsole/Attendance/camera_service.dart';
import 'package:team_dart_knights_sih/features/TeacherConsole/Attendance/face_detector.dart';
import 'package:team_dart_knights_sih/features/TeacherConsole/Attendance/mediapipe/anchors.dart';
import 'package:team_dart_knights_sih/features/TeacherConsole/Attendance/mediapipe/isolate_utils.dart';
import 'package:team_dart_knights_sih/features/TeacherConsole/Attendance/mediapipe/options_face.dart';
import 'package:team_dart_knights_sih/features/TeacherConsole/Attendance/ml_service.dart';
import 'package:team_dart_knights_sih/models/ModelProvider.dart';

import '../../../../injection_container.dart';
import '../../Attendance/mediapipe/model_inference_service.dart';

part 'attendance_state.dart';

class AttendanceCubit extends Cubit<AttendanceState> {
  final AWSApiClient apiClient;
  final IsolateUtils _isolateUtils = IsolateUtils();
  final VerificationStatus mode;
  final ModelInferenceService _modelInferenceService =
      getIt<ModelInferenceService>();
  final User teacher;
  final FaceDetectorService faceDetectorService;
  final MLService mlService;
  final CameraService cameraService;
  late final OptionsFace optionsFace;
  late final AnchorOption anchor;
  List<Student>? studList;
  Map<String, AttendanceStatus> attendanceMap = {};
  String? imagePath;
  Face? faceDetected;
  Size? imageSize;

  bool _detectingFaces = false;
  bool pictureTaken = false;

  // final ClassRoom classRoom;
  AttendanceCubit(
      {required this.apiClient,
      required this.faceDetectorService,
      required this.mlService,
      required this.cameraService,
      required this.mode,
      required this.teacher,
      this.studList})
      : super(AttendanceInitial()) {
    print(mode);

    if (mode == VerificationStatus.ManualAttendance) {
      initAttendance(studList!);
    } else if (mode == VerificationStatus.FaceVerified) {
      initCamera();
    } else if (mode == VerificationStatus.FaceDetectedAndVerified) {
      initServices(mode);
    } else {
      faceDetectorService.initialize();
      initializeInterPreter();
      initializeMediapipe();
    }
  }

  Future<void> initServices(VerificationStatus mode) async {
    if (mode == VerificationStatus.FaceDetectedAndVerified) {
      await initializeInterPreter();
      await initCamera();
      // await initializeMediapipe();
      faceDetectorService.initialize();
    }
  }

  Future<void> initCamera() async {
    emit(InitializingCamera());
    await cameraService.initialize();
    emit(CameraInitialized());
    emit(StudentNotSelected());
  }

  Future<void> initializeInterPreter() async {
    emit(InitializingMLModel());

    await mlService.initialize();

    print("model initializedb");
    emit(MLModelInitialized());
  }

  Future<Face> detectFaceFromImage(InputImage image) async {
    List<Face> faces =
        await faceDetectorService.faceDetector.processImage(image);
    print(faces[0].boundingBox);
    return faces[0];
  }

  void startPredicting() {
    imageSize = cameraService.getImageSize();
    print(imageSize);
    emit(StartingImageStream());
    cameraService.cameraController?.startImageStream((image) async {
      if (cameraService.cameraController != null) {
        if (_detectingFaces) return;

        _detectingFaces = true;

        try {
          await faceDetectorService.detectFacesFromImage(image);
          if (faceDetectorService.faces.isNotEmpty) {
            faceDetected = faceDetectorService.faces[0];
            // emit(FacesDetected());

            // mlService.setCurrentPrediction(image, faceDetected);

            emit(CurrentPredictionSet());
          } else {
            emit(NoFacesDetected());
          }

          _detectingFaces = false;
        } catch (e) {
          print(e);
          _detectingFaces = false;
        }
      }
    });
  }

  Future<void> addStudentFacialDataToDatabase(
      {required Student student}) async {
    List<dynamic> modelData = mlService.predictedData;
    print(modelData[0].runtimeType);
    final updatedStudent =
        student.copyWith(modelData: modelData as List<double>);
    final result =
        await apiClient.updateStudent(updatedStudent: updatedStudent);
    print(result);
  }

  void toggleAttendance(String id) {
    attendanceMap[id] = attendanceMap[id] == AttendanceStatus.Absent
        ? AttendanceStatus.Present
        : AttendanceStatus.Absent;

    emit(AttendanceToggled(attendance: attendanceMap));
  }

  Future<void> initAttendance(List<Student> studentList) async {
    for (var everyStudent in studentList) {
      attendanceMap.putIfAbsent(
          everyStudent.studentID, () => AttendanceStatus.Present);
    }
  }

  Future<void> studentGotSelected({required Student student}) async {
    emit(StudentSelected(student: student));
  }

  Future<void> uploadManualAttendance({required ClassRoom classRoom}) async {
    emit(UploadingAttendance());
    final position = await determinePosition();
    final double latitude = position.latitude;
    final double longitude = position.longitude;
    print(latitude);
    print(longitude);

    for (var studentID in attendanceMap.entries) {
      var sutdentName = studList!
          .firstWhere((element) => element.studentID == studentID.key)
          .studentName;

      var status = attendanceMap[studentID.value] == AttendanceStatus.Present
          ? AttendanceStatus.Present
          : AttendanceStatus.Absent;
      final attendance = getAttendanceObj(
          studentName: sutdentName,
          className: classRoom.classRoomName,
          mode: mode,
          attendanceStatus: status,
          latitude: latitude,
          longitude: longitude,
          classID: classRoom.id,
          studentID: studentID.key);
      final uploadedAttendance =
          await apiClient.createAttendance(attendance: attendance);
      // print(attendance);
    }
    final percent = (presentStudents / attendanceMap.length) * 100;
    final classAttendance = ClassAttendance(
        classID: classRoom.id,
        date: TemporalDate(DateTime.now()),
        presentPercent: presentStudents.toDouble(),
        teacherEmail: teacher.email);
    final uploadedClassAttendance =
        await apiClient.createClassAttendance(classAttendance: classAttendance);
    // print(classAttendance);
    final updatedClassRoom =
        classRoom.copyWith(currentAttendanceDate: TemporalDate(DateTime.now()));
    final res = await apiClient.updateClassRoom(classRoom: updatedClassRoom);
    emit(AttendanceUploaded());
  }

  Attendance getAttendanceObj(
      {required VerificationStatus mode,
      required AttendanceStatus attendanceStatus,
      required double latitude,
      required double longitude,
      required String classID,
      required String className,
      required String studentName,
      required String studentID}) {
    final Attendance attendance = Attendance(
      geoLatitude: latitude,
      geoLongitude: longitude,
      studentName: studentName,
      className: className,
      classID: classID,
      date: TemporalDate(DateTime.now()),
      status: attendanceStatus,
      studentID: studentID,
      teacherID: teacher.email,
      teacherName: teacher.name,
      time: TemporalTime(DateTime.now()),
      verification: mode,
    );
    return attendance;
  }

  int get presentStudents {
    var count = 0;
    var present = attendanceMap.entries.forEach((element) {
      if (element.value == AttendanceStatus.Present) {
        count++;
      }
    });
    return count;
  }

  //Mediapipe
  Future<void> initializeMediapipe() async {
    await _isolateUtils.initIsolate();
    _modelInferenceService.setModelConfig(0);
    // await cameraService.cameraController!.buildPreview();
    emit(InitializedAllServices());
  }

  var isPredicting = false;
  CameraImage? _cameraImage;
  Rect? face;
  void startPredictingMediaPipe(BuildContext context) {
    isPredicting = true;
    imageSize = cameraService.getImageSize();
    emit(StartingImageStream());
    cameraService.cameraController?.startImageStream((cameraImage) async {
      _cameraImage = cameraImage;

      if (cameraService.cameraController != null) {
        if (_detectingFaces) return;

        _detectingFaces = true;
        await _inference(cameraImage: cameraImage);

        // try {
        //   if (_modelInferenceService.inferenceResults != null) {
        //     mlService.setCurrentPrediction(
        //         cameraImage, _modelInferenceService.inferenceResults!['bbox']);

        //     await mlService.predict();
        //     print(mlService.predictedData);

        //     emit(CurrentPredictionSet());
        //   } else {
        //     emit(NoFacesDetected());
        //   }

        //   _detectingFaces = false;
        // } catch (e) {
        //   print(e);
        //   _detectingFaces = false;
        // }
      }
    });
  }

  // void facialDataMediapipeUpload(BuildContext context) {
  //   isPredicting = true;
  //   imageSize = cameraService.getImageSize();

  //   print(imageSize);
  //   emit(StartingImageStream());
  //   print("started image stream");
  //   cameraService.cameraController?.startImageStream((cameraImage) async {
  //     if (cameraService.cameraController != null) {
  //       if (_detectingFaces) return;

  //       _detectingFaces = true;
  //       await _inference(cameraImage: cameraImage);

  //       try {
  //         // await faceDetectorService.detectFacesFromImage(image);
  //         // if (faceDetectorService.faces.isNotEmpty) {
  //         //   faceDetected = faceDetectorService.faces[0];
  //         if (_modelInferenceService.inferenceResults != null) {
  //           mlService.setCurrentPrediction(
  //               cameraImage, _modelInferenceService.inferenceResults!['bbox']);

  //           print(mlService.predictedData);

  //           emit(CurrentPredictionSet());
  //         } else {
  //           emit(NoFacesDetected());
  //         }

  //         _detectingFaces = false;
  //       } catch (e) {
  //         print(e);
  //         _detectingFaces = false;
  //       }
  //     }
  //   });
  // }

  Future<void> _inference({required CameraImage cameraImage}) async {
    // if (!mounted) return;

    if (_modelInferenceService.model.interpreter != null) {
      // if (_detectingFaces) {
      //   return;
      // }

      _detectingFaces = true;

      await _modelInferenceService.inference(
        isolateUtils: _isolateUtils,
        cameraImage: cameraImage,
      );

      print(_modelInferenceService.inferenceResults);
      if (_modelInferenceService.inferenceResults != null) {
        face = _modelInferenceService.inferenceResults?['bbox'];
        emit(FacesDetected(
            cameraImage, _modelInferenceService.inferenceResults?['bbox']));
      }

      _detectingFaces = false;
    } else {
      print("interpreter is null");
    }
  }

  Future<void> setCurrentPrediction({Face? detectedFace,}) async {
    print('Setting current prediction');
    face = detectedFace!.boundingBox;
    mlService.setCurrentPrediction(_cameraImage!, face);
    emit(CurrentPredictionSet());
  }

  Future<void> compareDetectedResults() async {
    emit(ComparingResults());
    final result = await mlService.predict();
    if (result == null) {
      print('student not recognized');
      emit(StudentNotRecognized());
    } else {
      print('attendance marked for student : $result');
      emit(AttendanceMarked(student: result));
    }
  }

  void disposeIsolate() {
    _isolateUtils.dispose();
  }

  Map<String, dynamic>? get inferenceResults {
    _modelInferenceService.inferenceResults;
    return null;
  }
}

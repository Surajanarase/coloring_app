// lib/pages/mini_quiz_page.dart
import 'package:flutter/material.dart';
import '../services/db_service.dart';

class QuizQuestion {
  final String question;
  final List<String> options;
  final int correctAnswer;
  final String explanation;

  QuizQuestion({
    required this.question,
    required this.options,
    required this.correctAnswer,
    required this.explanation,
  });
}

class MiniQuizPage extends StatefulWidget {
  final String username;
  final String quizId;   // e.g. "mini1", "mini2", ...
  final int quizNumber;  // 1..4

  const MiniQuizPage({
    super.key,
    required this.username,
    required this.quizId,
    required this.quizNumber,
  });

  @override
  State<MiniQuizPage> createState() => _MiniQuizPageState();
}

class _MiniQuizPageState extends State<MiniQuizPage> {
  final DbService _db = DbService();

  int _currentQuestionIndex = 0;
  int? _selectedAnswer;
  bool _showResult = false;
  int _score = 0;

  late final List<QuizQuestion> _questions;
  late final List<int?> _userAnswers;

  @override
  void initState() {
    super.initState();
    _db.setCurrentUser(widget.username);
    _questions = _buildQuestionsForMiniQuiz(widget.quizNumber);
    _userAnswers = List<int?>.filled(_questions.length, null);
  }

  List<QuizQuestion> _buildQuestionsForMiniQuiz(int quizNumber) {
    // 3 short, child-friendly questions for each mini quiz
    switch (quizNumber) {
      case 1:
        return [
          QuizQuestion(
            question: "If your throat hurts a lot, what should you do?",
            options: [
              "Keep playing outside",
              "Tell an adult and go to the clinic",
              "Drink only cold water",
              "Ignore it"
            ],
            correctAnswer: 1,
            explanation:
                "When your throat hurts, you should always tell an adult and go to the clinic for proper medicine.",
          ),
          QuizQuestion(
            question: "Why should you not ignore a sore throat?",

            options: [
              "It can lead to a sick heart if not treated",
              "It is never serious",
              "Only adults should worry",
              "You don’t need medicine"
            ],
            correctAnswer: 0,
            explanation:
                "A sore throat that is not treated can cause rheumatic fever and damage the heart.",
          ),
          QuizQuestion(
            question: "Who can get a sore throat?",
            options: [
              "Only children",
              "Only teachers",
              "Both children and adults",
              "No one"
            ],
            correctAnswer: 2,
            explanation:
                "Children and adults can both get sore throats, so everyone should go to the clinic if it hurts.",
          ),
        ];
      case 2:
        return [
          QuizQuestion(
            question: "Which helper gives the best medicine for a sore throat?",
            options: [
              "The clinic nurse or doctor",
              "A friend at school",
              "A neighbour without training",
              "Watching TV"
            ],
            correctAnswer: 0,
            explanation:
                "Nurses and doctors at the clinic know which medicine is safe and correct.",
          ),
          QuizQuestion(
            question: "What can happen if you stop medicine too early?",
            options: [
              "You become taller",
              "The germs can come back and hurt your heart",
              "Nothing happens",
              "You never get sick again"
            ],
            correctAnswer: 1,
            explanation:
                "If you stop medicine early, the germs can come back and cause rheumatic fever or heart problems.",
          ),
          QuizQuestion(
            question: "How long should you usually take medicine for sore throat?",
            options: [
              "Only 1 day",
              "Until friends tell you to stop",
              "For all 10 days as told",
              "Only when you feel pain"
            ],
            correctAnswer: 2,
            explanation:
                "You must take the medicine for the full 10 days exactly as the clinic tells you.",
          ),
        ];
      case 3:
        return [
          QuizQuestion(
            question: "Which sign can show rheumatic fever?",
            options: [
              "Happy and running easily",
              "Pain in knees and elbows",
              "Only hungry",
              "Hair growing fast"
            ],
            correctAnswer: 1,
            explanation:
                "Joint pain, like in knees and elbows, can be a sign of rheumatic fever after a sore throat.",
          ),
          QuizQuestion(
            question: "How might Maria feel when her heart is sick?",
            options: [
              "Very strong all the time",
              "Gets tired quickly when playing",
              "Never needs rest",
              "Always wants to run"
            ],
            correctAnswer: 1,
            explanation:
                "When the heart is weak, children can feel tired quickly and cannot play for long.",
          ),
          QuizQuestion(
            question: "Who should you tell if you feel chest pain or can’t breathe well?",
            options: [
              "No one",
              "Only your friend",
              "An adult and clinic staff",
              "Your pet"
            ],
            correctAnswer: 2,
            explanation:
                "Always tell a trusted adult and go to the clinic if you have chest pain or trouble breathing.",
          ),
        ];
      case 4:
      default:
        return [
          QuizQuestion(
            question: "Why do we draw and learn about Maria’s story?",
            options: [
              "Only for fun pictures",
              "To learn how to keep our heart safe",
              "To skip school",
              "To avoid going to the clinic"
            ],
            correctAnswer: 1,
            explanation:
                "Maria’s story helps children learn how to protect their hearts by visiting the clinic early.",
          ),
          QuizQuestion(
            question: "What should you do if your friend has a very sore throat?",
            options: [
              "Tell them to play more",
              "Say nothing",
              "Tell a teacher or parent to take them to the clinic",
              "Give them sweets"
            ],
            correctAnswer: 2,
            explanation:
                "You can help by telling an adult so your friend can go to the clinic and get medicine.",
          ),
          QuizQuestion(
            question: "Which habit keeps your heart healthier?",
            options: [
              "Taking all medicines as told by the clinic",
              "Sharing leftover tablets with friends",
              "Stopping medicine when you feel okay",
              "Using only home remedies"
            ],
            correctAnswer: 0,
            explanation:
                "Taking all medicines exactly as told by the clinic helps protect your heart.",
          ),
        ];
    }
  }

  void _selectAnswer(int answer) {
    if (_showResult) return;
    setState(() {
      _selectedAnswer = answer;
    });
  }

  void _submitAnswer() {
    if (_selectedAnswer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an answer!')),
      );
      return;
    }

    setState(() {
      _userAnswers[_currentQuestionIndex] = _selectedAnswer;
      if (_selectedAnswer == _questions[_currentQuestionIndex].correctAnswer) {
        _score++;
      }
      _showResult = true;
    });
  }

  void _nextQuestion() {
    if (_currentQuestionIndex < _questions.length - 1) {
      setState(() {
        _currentQuestionIndex++;
        _selectedAnswer = _userAnswers[_currentQuestionIndex];
        _showResult = _userAnswers[_currentQuestionIndex] != null;
      });
    } else {
      _showFinalResults();
    }
  }

  Future<void> _showFinalResults() async {
  final percentage = (_score / _questions.length * 100).round();

  await _db.saveQuizResult(
    quizId: widget.quizId,
    score: _score,
    totalQuestions: _questions.length,
  );

  if (!mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) {
      final size = MediaQuery.of(dialogCtx).size;
      final isSmallHeight = size.height < 650;

      final message = percentage >= 90
          ? 'Super work! You are a heart hero!'
          : percentage >= 70
              ? 'Great job! You are learning how to protect your heart!'
              : 'Good try! Remember: always visit the clinic for a sore throat.';

      return AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 16),

        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),

          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              // 🚫 Removed the icon completely — Title only
              Text(
                'Mini Quiz ${widget.quizNumber} Completed!',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                softWrap: true,
              ),

              const SizedBox(height: 16),

              Text(
                'Your Score: $_score/${_questions.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                '$percentage%',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isSmallHeight ? 28 : 32,
                  fontWeight: FontWeight.w800,
                  color: percentage >= 70 ? Colors.green : Colors.orange,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                '🎉',
                style: TextStyle(fontSize: 44),
              ),

              const SizedBox(height: 20),

              // ✅ Small circular close button at center
              Center(
                child: InkWell(
                  onTap: () {
                    Navigator.of(dialogCtx).pop(); // close dialog
                    Navigator.of(dialogCtx).pop(); // go back to colouring page
                  },
                  borderRadius: BorderRadius.circular(40),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF58D3C7),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),
            ],
          ),
        ),
      );
    },
  );
}



  @override
  Widget build(BuildContext context) {
    final question = _questions[_currentQuestionIndex];
    final progress = (_currentQuestionIndex + 1) / _questions.length;

    final screenW = MediaQuery.of(context).size.width;
    final isSmall = screenW < 420;
    final headlineSize = isSmall ? 18.0 : 20.0;
    final optionFont = isSmall ? 14.0 : 16.0;
    final optionIconBase = isSmall ? 32.0 : 36.0;
    final resultIconSize = isSmall ? 24.0 : 28.0;
    final buttonFont = isSmall ? 16.0 : 18.0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFFE8F2), Color(0xFFE8F7FF), Color(0xFFEFF7EE)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          'Mini Quiz ${widget.quizNumber}',
          style: TextStyle(
            fontSize: headlineSize,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Progress Bar
            Container(
              margin: EdgeInsets.all(screenW * 0.04),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Question ${_currentQuestionIndex + 1}/${_questions.length}',
                        style: TextStyle(
                          fontSize: isSmall ? 14 : 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Score: $_score',
                        style: TextStyle(
                          fontSize: isSmall ? 14 : 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: screenW * 0.02),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: isSmall ? 8 : 10,
                      backgroundColor: Colors.grey.shade200,
                      color: Colors.teal,
                    ),
                  ),
                ],
              ),
            ),

            // Question Card
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: screenW * 0.04,
                  vertical: screenW * 0.03,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
  padding: EdgeInsets.all(isSmall ? 16 : 20),
  decoration: BoxDecoration(
    gradient: const LinearGradient(
      colors: [Color(0xFFFFF0F4), Color(0xFFEFFCF4)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      color: Colors.grey.shade300,
      width: 2,
    ),
    boxShadow: const [
      BoxShadow(
        color: Color(0x11000000),
        blurRadius: 10,
        offset: Offset(0, 4),
      ),
    ],
  ),
  child: Text(
    question.question,
    style: TextStyle(
      fontSize: headlineSize,
      fontWeight: FontWeight.w700,
      color: Colors.black87,
    ),
    textAlign: TextAlign.center,
  ),
),


                    SizedBox(height: screenW * 0.06),

                    // Options
                    ...List.generate(question.options.length, (index) {
                      final isSelected = _selectedAnswer == index;
                      final isCorrect = index == question.correctAnswer;

                      Color cardColor = Colors.white;
                      Color borderColor = Colors.grey.shade300;
                      IconData? icon;
                      Color? iconColor;

                      if (_showResult) {
                        if (isCorrect) {
                          cardColor = const Color(0xFFE8F5E9);
                          borderColor = Colors.green;
                          icon = Icons.check_circle;
                          iconColor = Colors.green;
                        } else if (isSelected && !isCorrect) {
                          cardColor = const Color(0xFFFFEBEE);
                          borderColor = Colors.red;
                          icon = Icons.cancel;
                          iconColor = Colors.red;
                        }
                      } else if (isSelected) {
                        cardColor = const Color(0xFFFFFBED);
                        borderColor = Colors.deepPurple;
                      }

                      return GestureDetector(
                        onTap: () => _selectAnswer(index),
                        child: Container(
                          margin: EdgeInsets.only(bottom: screenW * 0.03),
                          padding: EdgeInsets.all(isSmall ? 12 : 16),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: borderColor, width: 2),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x11000000),
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: optionIconBase,
                                height: optionIconBase,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.deepPurple
                                      : Colors.grey.shade200,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    String.fromCharCode(65 + index),
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.black87,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: screenW * 0.03),
                              Expanded(
                                child: Text(
                                  question.options[index],
                                  style: TextStyle(
                                    fontSize: optionFont,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (icon != null)
                                Padding(
                                  padding:
                                      EdgeInsets.only(left: screenW * 0.03),
                                  child: Icon(
                                    icon,
                                    color: iconColor,
                                    size: resultIconSize,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),

                    if (_showResult) ...[
                      SizedBox(height: screenW * 0.04),
                      Container(
                        padding: EdgeInsets.all(isSmall ? 12 : 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3F2FD),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.lightbulb,
                              color: Colors.orange,
                              size: resultIconSize,
                            ),
                            SizedBox(width: screenW * 0.03),
                            Expanded(
                              child: Text(
                                question.explanation,
                                style: TextStyle(
                                  fontSize: optionFont,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    SizedBox(height: screenW * 0.08),
                  ],
                ),
              ),
            ),

            // Buttons
            Padding(
              padding: EdgeInsets.all(screenW * 0.04),
              child: _showResult
                  ? SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _nextQuestion,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          padding: EdgeInsets.symmetric(
                            vertical: isSmall ? 14 : 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 4,
                        ),
                        child: Text(
                          _currentQuestionIndex < _questions.length - 1
                              ? 'Next Question'
                              : 'See Results',
                          style: TextStyle(
                            fontSize: buttonFont,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submitAnswer,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          padding: EdgeInsets.symmetric(
                            vertical: isSmall ? 14 : 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 4,
                        ),
                        child: Text(
                          'Submit Answer',
                          style: TextStyle(
                            fontSize: buttonFont,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// lib/pages/quiz_page.dart
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

class QuizPage extends StatefulWidget {
  final String username;

  const QuizPage({super.key, required this.username});

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  final DbService _db = DbService();

  int _currentQuestionIndex = 0;
  int? _selectedAnswer;
  bool _showResult = false;
  int _score = 0;
  final List<int?> _userAnswers = List.filled(10, null);

  final List<QuizQuestion> _questions = [
    QuizQuestion(
      question: "What should Maria do when she has a sore throat?",
      options: [
        "Wait and see if it gets better",
        "Go to the health clinic immediately",
        "Take a home remedy only",
        "Play with friends"
      ],
      correctAnswer: 1,
      explanation: "If you have a sore throat, you must go to the clinic immediately to get proper treatment.",
    ),
    QuizQuestion(
      question: "Can a home remedy stop rheumatic heart disease?",
      options: [
        "Yes, home remedies cure everything",
        "No, home remedies cannot stop rheumatic heart disease",
        "Only for children",
        "Sometimes it works"
      ],
      correctAnswer: 1,
      explanation: "A home remedy cannot stop a person from getting rheumatic fever or rheumatic heart disease. You need proper medical treatment.",
    ),
    QuizQuestion(
      question: "What happened to Maria's heart when she didn't get proper treatment?",
      options: [
        "Her heart became very sick",
        "Nothing happened",
        "It got stronger",
        "It healed on its own"
      ],
      correctAnswer: 0,
      explanation: "Maria's heart became very sick because she didn't get proper treatment for her sore throat at the clinic.",
    ),
    QuizQuestion(
      question: "How long should you take medicine for a sore throat?",
      options: [
        "1 day",
        "5 days",
        "10 days as directed",
        "Until you feel better"
      ],
      correctAnswer: 3,
      explanation: "You must take the medicine exactly as directed by Doctor, even if you start feeling better.",
    ),
    QuizQuestion(
      question: "What symptoms did Maria have besides a sore throat?",
      options: [
        "Fever and joint pain",
        "Only a cough",
        "Stomach ache",
        "Headache only"
      ],
      correctAnswer: 0,
      explanation: "Maria had a fever, and her elbows, knees, and other joints hurt. These are symptoms of rheumatic fever.",
    ),
    QuizQuestion(
      question: "What happened to Maria as she got older?",
      options: [
        "She could play more with friends",
        "She got tired easily and couldn't play",
        "She became a doctor",
        "Nothing changed"
      ],
      correctAnswer: 1,
      explanation: "As Maria got older, she got tired easily and couldn't play with her friends because her heart was sick.",
    ),
    QuizQuestion(
      question: "What problem did Maria have with breathing?",
      options: [
        "She could breathe normally",
        "It was hard for her to breathe",
        "She breathed too fast",
        "She only had trouble at night"
      ],
      correctAnswer: 1,
      explanation: "It was hard for Maria to breathe because rheumatic heart disease affected her heart.",
    ),
    QuizQuestion(
      question: "What treatment might Maria need for the rest of her life?",
      options: [
        "Only exercise",
        "Medication and possibly surgery",
        "Home remedies",
        "No treatment needed"
      ],
      correctAnswer: 1,
      explanation: "Maria will need to take medication for the rest of her life and may need surgery because of her rheumatic heart disease.",
    ),
    QuizQuestion(
      question: "Who should go to the clinic if they have a sore throat?",
      options: [
        "Only children",
        "Only adults",
        "Both children and adults",
        "Nobody needs to go"
      ],
      correctAnswer: 2,
      explanation: "If a child or adult has a sore throat, they must make sure to go to the clinic immediately.",
    ),
    QuizQuestion(
      question: "What can happen if a sore throat is not treated properly?",
      options: [
        "It will go away by itself",
        "It can lead to heart disease",
        "Nothing serious",
        "You get a cold"
      ],
      correctAnswer: 1,
      explanation: "If your sore throat is not treated, it can lead to heart disease. That's why you must visit a health clinic.",
    ),
  ];

  @override
  void initState() {
    super.initState();
    // ensure quiz results are stored for the correct user
    _db.setCurrentUser(widget.username);
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
    quizId: 'final',
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
          ? 'Excellent! You really understand how to protect your heart!'
          : percentage >= 70
              ? 'Great job! You learned a lot about heart health!'
              : 'Good effort! Remember to always visit the clinic for a sore throat.';

      return AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 16),

        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              // ✅ Centered Title — No icon
              Text(
                'Quiz Complete!',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 16),

              Text(
                'Your Score: $_score/${_questions.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                '$percentage%',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isSmallHeight ? 30 : 34,
                  fontWeight: FontWeight.w800,
                  color: percentage >= 70 ? Colors.green : Colors.orange,
                ),
              ),

              const SizedBox(height: 14),

              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 12),

              // 🎉 Big celebration emoji
              const Text(
                '🎉',
                style: TextStyle(
                  fontSize: 44,
                ),
              ),

              const SizedBox(height: 20),

              // ✅ Small Circular Close Button (center)
              Center(
                child: InkWell(
                  onTap: () {
                    Navigator.of(dialogCtx).pop(); // close popup
                    Navigator.of(dialogCtx).pop(); // go back 1 screen (dashboard)
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

    // responsive sizing derived from screen width (keeps all names/logic unchanged)
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
          'Heart Health Quiz',
          style: TextStyle(fontSize: headlineSize, fontWeight: FontWeight.w800, color: Colors.black87),
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
                        style: TextStyle(fontSize: isSmall ? 14 : 16, fontWeight: FontWeight.w600),
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
                padding: EdgeInsets.symmetric(horizontal: screenW * 0.04, vertical: screenW * 0.03),
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
                                  color: isSelected ? Colors.deepPurple : Colors.grey.shade200,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    String.fromCharCode(65 + index),
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.black87,
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
                                  padding: EdgeInsets.only(left: screenW * 0.03),
                                  child: Icon(icon, color: iconColor, size: resultIconSize),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),

                    // Explanation (shown after answer)
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
                            Icon(Icons.lightbulb, color: Colors.orange, size: resultIconSize),
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

                    // Add spacing at bottom for button
                    SizedBox(height: screenW * 0.08),
                  ],
                ),
              ),
            ),

            // Action Buttons - Removed white box background
            Padding(
              padding: EdgeInsets.all(screenW * 0.04),
              child: _showResult
                  ? SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _nextQuestion,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          padding: EdgeInsets.symmetric(vertical: isSmall ? 14 : 16),
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
                          padding: EdgeInsets.symmetric(vertical: isSmall ? 14 : 16),
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

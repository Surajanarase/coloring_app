// lib/pages/quiz_page.dart
import 'package:flutter/material.dart';

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
      explanation: "You must take the medicine exactly as directed for the full 10 days, even if you start feeling better.",
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

  void _showFinalResults() {
    final percentage = (_score / _questions.length * 100).round();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              percentage >= 70 ? Icons.emoji_events : Icons.info_outline,
              color: percentage >= 70 ? Colors.amber : Colors.blue,
              size: 32,
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Quiz Complete!')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Your Score: $_score/${_questions.length}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '$percentage%',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: percentage >= 70 ? Colors.green : Colors.orange,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              percentage >= 90
                  ? 'Excellent! You really understand how to protect your heart! 🎉'
                  : percentage >= 70
                      ? 'Great job! You learned a lot about heart health! 👍'
                      : 'Good try! Remember to always go to the clinic for a sore throat! 💪',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Back to Dashboard'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final question = _questions[_currentQuestionIndex];
    final progress = (_currentQuestionIndex + 1) / _questions.length;

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
        title: const Text(
          'Heart Health Quiz',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.black87),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Progress Bar
            Container(
              margin: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Question ${_currentQuestionIndex + 1}/${_questions.length}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Score: $_score',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 10,
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
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFF0F4), Color(0xFFEFFCF4)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
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
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    const SizedBox(height: 24),

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
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
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
                                width: 32,
                                height: 32,
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
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  question.options[index],
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (icon != null)
                                Icon(icon, color: iconColor, size: 28),
                            ],
                          ),
                        ),
                      );
                    }),

                    // Explanation (shown after answer)
                    if (_showResult) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3F2FD),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.lightbulb, color: Colors.orange, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                question.explanation,
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    
                    // Add spacing at bottom for button
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),

            // Action Buttons - Removed white box background
            Padding(
              padding: const EdgeInsets.all(16),
              child: _showResult
                  ? SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _nextQuestion,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 4,
                        ),
                        child: Text(
                          _currentQuestionIndex < _questions.length - 1
                              ? 'Next Question'
                              : 'See Results',
                          style: const TextStyle(
                            fontSize: 18,
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
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 4,
                        ),
                        child: const Text(
                          'Submit Answer',
                          style: TextStyle(
                            fontSize: 18,
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
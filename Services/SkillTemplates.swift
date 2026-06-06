import Foundation

// MARK: - Master Cached System Prompt
// ~520 tokens — sent once per session, cached by Anthropic (90% cost reduction on cache hits)
// All exercise types handled by a single prompt to maximise cache reuse.

enum SkillTemplates {

    static let masterSystemPrompt = """
    You are LinguaTutor, an expert CEFR-aligned language teacher for:
    - Marathi (code: mr, script: Devanagari, locale: mr-IN)
    - Swedish (code: sv, script: Latin, locale: sv-SE)
    - Punjabi (code: pa, script: Gurmukhi, locale: pa-IN)

    ALWAYS respond with valid JSON only. No markdown, no extra text, no code fences.

    === COMMANDS AND RESPONSE SCHEMAS ===

    EVAL: Evaluate a user answer. Input: EVAL|<type>|<lang>|<level>|<prompt>|<user_answer>
    Response: {"score":0.0-1.0,"correct":true/false,"feedback":"≤40 words, encouraging","correction":"corrected form in target lang, if wrong, else null","hint":"optional next tip or null"}

    LESSON: Generate a mini-lesson. Input: LESSON|<lang>|<level>|<focus_skill>
    Response: {"title":"lesson title","exercises":[{"type":"vocab|grammar|translate","prompt":"exercise text","answer":"expected answer","hint":"one line tip or null"},…]} — produce exactly 8 exercises.

    TEST: Generate a placement or skill test question. Input: TEST|<lang>|<level>|<skill>|<question_num>
    Response: {"question":"question text in English and target lang","options":["A","B","C","D"],"correct":0-3,"explanation":"≤25 words"}

    SPEAK: Evaluate a speech transcription for accuracy. Input: SPEAK|<lang>|<level>|<expected>|<transcribed>
    Response: {"score":0.0-1.0,"correct":true/false,"feedback":"≤30 words","correction":"null or corrected phrase in target lang","pronunciation_note":"≤15 words on what to improve or null"}

    === CEFR LEVEL MAPPING ===
    A1: numbers 1-20, colours, family members, basic greetings, "I am / I have"
    A2: daily routine, food, shopping, weather, simple past, telling time
    B1: opinions, future plans, travel, work, comparatives, conditional basics
    B2: abstract topics, politics, environment, complex conditionals, reported speech
    C1: nuanced expression, idioms, formal register, complex syntax, hypotheticals
    C2: near-native mastery, subtle register shifts, cultural references, humour

    === SCORING GUIDE ===
    1.0 = perfect (accept minor spelling if clearly correct intent)
    0.8 = minor grammatical or spelling error, meaning preserved
    0.6 = partially correct, main idea present but significant errors
    0.4 = mostly wrong, only fragments correct
    0.2 = incorrect but attempts target language
    0.0 = unintelligible or no attempt

    Be encouraging and concise. Never exceed the word limits above.
    """

    // MARK: - Command Builders (compact strings → minimal tokens per call)

    static func evalCommand(
        type: ExerciseType,
        language: Language,
        level: CEFRLevel,
        prompt: String,
        userAnswer: String
    ) -> String {
        "EVAL|\(type.rawValue)|\(language.code)|\(level.rawValue)|\(prompt)|\(userAnswer)"
    }

    static func lessonCommand(
        language: Language,
        level: CEFRLevel,
        focusSkill: ExerciseType
    ) -> String {
        "LESSON|\(language.code)|\(level.rawValue)|\(focusSkill.rawValue)"
    }

    static func testCommand(
        language: Language,
        level: CEFRLevel,
        skill: ExerciseType,
        questionNumber: Int
    ) -> String {
        "TEST|\(language.code)|\(level.rawValue)|\(skill.rawValue)|\(questionNumber)"
    }

    static func speakCommand(
        language: Language,
        level: CEFRLevel,
        expected: String,
        transcribed: String
    ) -> String {
        "SPEAK|\(language.code)|\(level.rawValue)|\(expected)|\(transcribed)"
    }

    // MARK: - Fallback Exercise Seeds (used when API is unavailable)
    // These are static so the app still works offline.

    static let a1VocabSeeds: [Language: [(String, String)]] = [
        .swedish: [
            ("Hej", "Hello"), ("Tack", "Thank you"), ("Ja", "Yes"), ("Nej", "No"),
            ("Vatten", "Water"), ("Mat", "Food"), ("Hus", "House"), ("Bil", "Car"),
            ("Dag", "Day"), ("Natt", "Night")
        ],
        .marathi: [
            ("नमस्कार", "Namaste / Hello"), ("धन्यवाद", "Thank you"), ("हो", "Yes"), ("नाही", "No"),
            ("पाणी", "Water"), ("अन्न", "Food"), ("घर", "House"), ("गाडी", "Car"),
            ("दिवस", "Day"), ("रात्र", "Night")
        ],
        .punjabi: [
            ("ਸਤ ਸ੍ਰੀ ਅਕਾਲ", "Hello / Good day"), ("ਧੰਨਵਾਦ", "Thank you"), ("ਹਾਂ", "Yes"), ("ਨਹੀਂ", "No"),
            ("ਪਾਣੀ", "Water"), ("ਖਾਣਾ", "Food"), ("ਘਰ", "House"), ("ਗੱਡੀ", "Car"),
            ("ਦਿਨ", "Day"), ("ਰਾਤ", "Night")
        ]
    ]

    // Used for listening exercises — the app speaks these and user must transcribe/answer
    static let a1ListeningPrompts: [Language: [(String, String)]] = [
        .swedish: [
            ("Vad heter du?", "What is your name?"),
            ("Hur mår du?", "How are you?"),
            ("Var bor du?", "Where do you live?")
        ],
        .marathi: [
            ("तुमचं नाव काय आहे?", "What is your name?"),
            ("तुम्ही कसे आहात?", "How are you?"),
            ("तुम्ही कुठे राहता?", "Where do you live?")
        ],
        .punjabi: [
            ("ਤੁਹਾਡਾ ਨਾਮ ਕੀ ਹੈ?", "What is your name?"),
            ("ਤੁਸੀਂ ਕਿਵੇਂ ਹੋ?", "How are you?"),
            ("ਤੁਸੀਂ ਕਿੱਥੇ ਰਹਿੰਦੇ ਹੋ?", "Where do you live?")
        ]
    ]
}

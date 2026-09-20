#import "LanguageModel.h"
#include <algorithm>
#include <cmath>
#include <string>
#include <unordered_map>
#include <vector>
#include <zlib.h>

@implementation NppLanguageGuess
@end

const NSUInteger NppMostLanguagesToOffer = 10;
const NSUInteger NppShortListLength = 3;

/// Only the beginning of a long text is read. It is enough to tell what the
/// text is, and walking a large file to the end would slow opening it.
static const NSUInteger kSampleCharacters = 64 * 1024;

/// Below this there is nothing to judge by.
static const NSUInteger kLeastBytes = 40;

// The tags in the top byte of a feature key. Byte n-grams carry their own size
// there; the rest are hashed.
enum { kTagWord = 5, kTagFirstWord = 6, kTagLineShape = 7, kTagWordPair = 8 };
static const size_t kWordLength = 24, kFirstWordLength = 16, kPairWordLength = 16;

@implementation NppLanguageModel {
    std::vector<std::string> _languages;
    std::vector<uint64_t> _keys;         // ascending
    std::vector<float> _idf;             // one per feature
    std::vector<float> _bias;            // one per language
    std::vector<float> _scale;           // one per language
    std::vector<int8_t> _weights;        // languages * features, row-major
    std::vector<uint8_t> _ngramSizes;
    uint32_t _featureCount;
    float _temperature, _halfEvidence, _coverage, _single;
    BOOL _independent;   // one yes-or-no per language, rather than one choice among all
}

#pragma mark - Reading the file

static BOOL Take(const uint8_t *bytes, NSUInteger length, NSUInteger *at, void *into, NSUInteger wanted) {
    if (*at + wanted > length) return NO;
    memcpy(into, bytes + *at, wanted);
    *at += wanted;
    return YES;
}

+ (instancetype)modelWithContentsOfFile:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
    if (!data.length) return nil;
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger length = data.length, at = 0;

    char magic[8] = {0};
    if (!Take(bytes, length, &at, magic, sizeof(magic))) return nil;
    // Version 5 adds the level one language needs to be offered alone.
    if (memcmp(magic, "NPPLANG", 7) != 0 || (magic[7] != 4 && magic[7] != 5)) return nil;
    BOOL hasSingle = magic[7] == 5;

    uint32_t languageCount = 0, featureCount = 0;
    uint8_t ngramCount = 0, flags = 0;
    float temperature = 1, half = 0, coverage = 0.9f, single = 0;
    if (!Take(bytes, length, &at, &languageCount, 4) || !Take(bytes, length, &at, &featureCount, 4) ||
        !Take(bytes, length, &at, &ngramCount, 1) || !Take(bytes, length, &at, &flags, 1) ||
        !Take(bytes, length, &at, &temperature, 4) || !Take(bytes, length, &at, &half, 4) ||
        !Take(bytes, length, &at, &coverage, 4)) return nil;
    if (hasSingle && !Take(bytes, length, &at, &single, 4)) return nil;
    if (!languageCount || !featureCount || !ngramCount || ngramCount > 7) return nil;

    NppLanguageModel *model = [[NppLanguageModel alloc] init];
    model->_featureCount = featureCount;
    model->_temperature = temperature > 0 ? temperature : 1;
    model->_halfEvidence = MAX(0.0f, half);
    model->_coverage = coverage > 0 && coverage <= 1 ? coverage : 0.9f;
    model->_single = single >= model->_coverage && single <= 1 ? single : model->_coverage;
    model->_independent = (flags & 2) != 0;
    model->_ngramSizes.resize(ngramCount);
    if (!Take(bytes, length, &at, model->_ngramSizes.data(), ngramCount)) return nil;
    for (uint8_t size : model->_ngramSizes) if (size < 1 || size > 7) return nil;

    for (uint32_t i = 0; i < languageCount; ++i) {
        uint16_t size = 0;
        if (!Take(bytes, length, &at, &size, 2) || at + size > length) return nil;
        model->_languages.emplace_back((const char *)bytes + at, size);
        at += size;
    }

    model->_keys.resize(featureCount);
    if (!Take(bytes, length, &at, model->_keys.data(), (NSUInteger)featureCount * 8)) return nil;
    if (!std::is_sorted(model->_keys.begin(), model->_keys.end())) return nil;

    model->_idf.resize(featureCount);
    for (uint32_t i = 0; i < featureCount; ++i) {
        int16_t raw = 0;
        if (!Take(bytes, length, &at, &raw, 2)) return nil;
        model->_idf[i] = raw / 100.0f;
    }
    model->_bias.resize(languageCount);
    if (!Take(bytes, length, &at, model->_bias.data(), (NSUInteger)languageCount * 4)) return nil;

    model->_scale.resize(languageCount);
    model->_weights.resize((size_t)languageCount * featureCount);
    for (uint32_t language = 0; language < languageCount; ++language) {
        if (!Take(bytes, length, &at, &model->_scale[language], 4)) return nil;
        if (!Take(bytes, length, &at, &model->_weights[(size_t)language * featureCount], featureCount)) return nil;
    }
    return model;
}

+ (instancetype)sharedModel {
    static NppLanguageModel *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [[NSBundle mainBundle] pathForResource:@"language-model" ofType:@"bin"];
        if (path) shared = [NppLanguageModel modelWithContentsOfFile:path];
    });
    return shared;
}

- (NSArray<NSString *> *)languageNames {
    NSMutableArray *names = [NSMutableArray arrayWithCapacity:_languages.size()];
    for (const std::string &name : _languages) [names addObject:@(name.c_str())];
    return names;
}

- (double)coverage { return _coverage; }
- (double)singleLevel { return _single; }

#pragma mark - Measuring a piece of text, the way the trainer does

/// Line endings to LF, runs of blanks to one space, numbers to one zero.
static std::string Normalised(NSString *text) {
    NSString *head = text.length > kSampleCharacters ? [text substringToIndex:kSampleCharacters] : text;
    const char *utf8 = head.UTF8String;
    if (!utf8) return std::string();
    std::string out;
    out.reserve(strlen(utf8));
    bool inBlanks = false, inDigits = false;
    for (const char *c = utf8; *c; ++c) {
        if (*c == '\r') {
            if (c[1] != '\n') out.push_back('\n');
            inBlanks = inDigits = false;
            continue;
        }
        if (*c == ' ' || *c == '\t') {
            if (!inBlanks) out.push_back(' ');
            inBlanks = true;
            inDigits = false;
            continue;
        }
        inBlanks = false;
        if (*c >= '0' && *c <= '9') {
            if (!inDigits) out.push_back('0');
            inDigits = true;
            continue;
        }
        inDigits = false;
        out.push_back(*c);
    }
    return out;
}

static inline bool IsWordStart(uint8_t c) {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_';
}
static inline bool IsWordByte(uint8_t c) { return IsWordStart(c) || (c >= '0' && c <= '9'); }

static inline uint8_t ShapeOf(uint8_t c) {
    if (IsWordStart(c)) return 97;
    if (c >= '0' && c <= '9') return 48;
    return c < 128 ? c : 128;
}

static inline uint64_t Keyed(uint64_t tag, const uint8_t *bytes, size_t length) {
    uint64_t crc = crc32(0L, bytes, (uInt)length);
    return (tag << 56) | (crc << 8) | (length & 0xFF);
}

/// Every feature key of the text, with how often each occurs.
- (void)collectKeysOf:(const std::string &)sample into:(std::unordered_map<uint64_t, uint32_t> &)counts {
    const uint8_t *bytes = (const uint8_t *)sample.data();
    size_t length = sample.size();

    for (uint8_t size : _ngramSizes) {
        if (length < size) continue;
        for (size_t i = 0; i + size <= length; ++i) {
            uint64_t packed = 0;
            for (size_t j = 0; j < size; ++j) packed = (packed << 8) | bytes[i + j];
            counts[((uint64_t)size << 56) | packed] += 1;
        }
    }

    for (size_t i = 0; i < length;) {
        if (!IsWordStart(bytes[i])) { ++i; continue; }
        size_t start = i;
        while (i < length && IsWordByte(bytes[i])) ++i;
        counts[Keyed(kTagWord, bytes + start, MIN(i - start, kWordLength))] += 1;
    }

    size_t lineStart = 0;
    while (lineStart <= length) {
        size_t lineEnd = lineStart;
        while (lineEnd < length && bytes[lineEnd] != '\n') ++lineEnd;
        size_t from = lineStart, to = lineEnd;
        while (from < to && bytes[from] == ' ') ++from;
        while (to > from && bytes[to - 1] == ' ') --to;
        if (to > from) {
            uint8_t shape[2] = {ShapeOf(bytes[from]), ShapeOf(bytes[to - 1])};
            counts[Keyed(kTagLineShape, shape, 2)] += 1;
            if (IsWordStart(bytes[from])) {
                size_t wordEnd = from;
                while (wordEnd < to && IsWordByte(bytes[wordEnd])) ++wordEnd;
                counts[Keyed(kTagFirstWord, bytes + from, MIN(wordEnd - from, kFirstWordLength))] += 1;
            }
            // Neighbouring words of the line, each cut to sixteen bytes, with a
            // space between: "public enum", "let mut" - as the trainer pairs them.
            uint8_t pair[2 * kPairWordLength + 1];
            size_t previousLength = 0;
            for (size_t i = from; i < to;) {
                if (!IsWordStart(bytes[i])) { ++i; continue; }
                size_t start = i;
                while (i < to && IsWordByte(bytes[i])) ++i;
                size_t wordLength = MIN(i - start, (size_t)kPairWordLength);
                if (previousLength) {
                    pair[previousLength] = ' ';
                    memcpy(pair + previousLength + 1, bytes + start, wordLength);
                    counts[Keyed(kTagWordPair, pair, previousLength + 1 + wordLength)] += 1;
                }
                memcpy(pair, bytes + start, wordLength);
                previousLength = wordLength;
            }
        }
        lineStart = lineEnd + 1;
    }
}

/// The scores of every language for the text, and how many features the model
/// recognised in it. Empty when there is nothing to judge by.
- (std::vector<double>)scoresOf:(NSString *)text evidence:(NSUInteger *)evidence {
    *evidence = 0;
    if (_languages.empty()) return {};
    std::string sample = Normalised(text);
    if (sample.size() < kLeastBytes) return {};

    std::unordered_map<uint64_t, uint32_t> counts;
    counts.reserve(8192);
    [self collectKeysOf:sample into:counts];

    // Weighted and pointed the way the training examples were, so that what
    // is compared is the shape of the text rather than how much of it there is.
    std::vector<std::pair<uint32_t, float>> query;
    double magnitude = 0;
    for (const auto &pair : counts) {
        auto found = std::lower_bound(_keys.begin(), _keys.end(), pair.first);
        if (found == _keys.end() || *found != pair.first) continue;
        uint32_t index = (uint32_t)(found - _keys.begin());
        float value = std::log1p((float)pair.second) * _idf[index];
        query.emplace_back(index, value);
        magnitude += (double)value * value;
    }
    if (query.empty()) return {};
    magnitude = std::sqrt(magnitude);
    for (auto &pair : query) pair.second = (float)(pair.second / magnitude);
    *evidence = query.size();

    std::vector<double> scores(_languages.size());
    for (size_t language = 0; language < _languages.size(); ++language) {
        const int8_t *row = &_weights[language * _featureCount];
        double total = 0;
        for (const auto &pair : query) total += row[pair.first] * pair.second;
        scores[language] = _bias[language] + total * _scale[language] / 127.0;
    }
    return scores;
}

- (NSArray<NppLanguageGuess *> *)guessesForText:(NSString *)text {
    NSUInteger evidence = 0;
    std::vector<double> scores = [self scoresOf:text evidence:&evidence];
    if (scores.empty()) return @[];

    // Turned into likelihoods at the scale the trainer fitted: sharper the
    // more of the text the model recognised, so that a few lines never come
    // out as sure as a whole file. With independent judgements each language
    // has its own, and a text two languages could have written scores well
    // for both; otherwise they are shares of one whole.
    double scale = _temperature * (double)evidence / ((double)evidence + _halfEvidence);
    double largest = *std::max_element(scores.begin(), scores.end());
    std::vector<double> shares(scores.size());
    double sum = 0;
    for (size_t i = 0; i < scores.size(); ++i) {
        if (_independent) {
            shares[i] = 1.0 / (1.0 + std::exp(-scores[i] * scale));
        } else {
            shares[i] = std::exp((scores[i] - largest) * scale);
            sum += shares[i];
        }
    }
    if (_independent) sum = 1.0;

    NSMutableArray<NppLanguageGuess *> *guesses = [NSMutableArray arrayWithCapacity:scores.size()];
    for (size_t i = 0; i < scores.size(); ++i) {
        NppLanguageGuess *guess = [[NppLanguageGuess alloc] init];
        guess.name = @(_languages[i].c_str());
        guess.score = scores[i];
        guess.confidence = sum > 0 ? shares[i] / sum : 0;
        [guesses addObject:guess];
    }
    [guesses sortUsingComparator:^NSComparisonResult(NppLanguageGuess *a, NppLanguageGuess *b) {
        if (a.confidence == b.confidence) return [a.name compare:b.name];
        return a.confidence > b.confidence ? NSOrderedAscending : NSOrderedDescending;
    }];
    return guesses;
}

- (NSArray<NSString *> *)languagesOfferedForText:(NSString *)text {
    NSArray<NppLanguageGuess *> *guesses = [self guessesForText:text];
    if (!guesses.count) return nil;

    // With independent judgements, every language that reaches the level;
    // otherwise the fewest, best first, whose shares add up to the coverage.
    NSMutableArray<NSString *> *offered = [NSMutableArray array];
    double reached = 0;
    for (NppLanguageGuess *guess in guesses) {
        if (_independent && guess.confidence < _coverage - 1e-9) break;
        [offered addObject:guess.name];
        reached += guess.confidence;
        if (!_independent && reached >= _coverage - 1e-9) break;
        if (offered.count > NppMostLanguagesToOffer) return @[];
    }
    // One language not sure enough to be applied alone comes with the next
    // best, as a short list to choose from.
    if (_independent && offered.count == 1 && guesses.firstObject.confidence < _single - 1e-9) {
        [offered removeAllObjects];
        for (NppLanguageGuess *guess in guesses) {
            if (offered.count == NppShortListLength) break;
            [offered addObject:guess.name];
        }
    }
    return offered.count > NppMostLanguagesToOffer ? @[] : offered;
}

@end

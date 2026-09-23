// Boost.Regex as the ComparePlus engine uses it, over the standard library:
// a wide regex with Perl syntax, case folding, and a match iterator.
#pragma once
#include <regex>
namespace boost {
    using wregex = std::wregex;
    template <typename It> using regex_iterator = std::regex_iterator<It>;
    struct regex {
        static constexpr std::regex_constants::syntax_option_type perl = std::regex_constants::ECMAScript;
        static constexpr std::regex_constants::syntax_option_type optimize = std::regex_constants::optimize;
        static constexpr std::regex_constants::syntax_option_type icase = std::regex_constants::icase;
    };
}

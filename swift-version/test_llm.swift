import Foundation
#if canImport(LanguageModel)
import LanguageModel
print("LanguageModel available")
#else
print("LanguageModel NOT available")
#endif

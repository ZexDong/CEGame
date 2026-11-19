#if UNITY_EDITOR
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace GameCreate.Stormbound.Evaluator
{
    // Text semantics for the declared missing-local-Workshop construction
    // trajectory. These functions do not inspect candidate state or wiring.
    public static class ConstructionFeedbackObservation
    {
        const string Noun = @"(?:(?:a|an|the|one|local|completed|complete|built|operational|functioning)\s+){0,5}workshop\b";
        static bool Explanation(string value)
        {
            var text=PresentationObservers.SemanticText(value).ToLowerInvariant();
            // A bare label or a negated requirement is not an explanation for
            // refusing this action, even when other visible text changes.
            if(Regex.IsMatch(text,@"\b(?:no|not)\s+(?:\w+\s+){0,3}workshop\s+(?:is\s+)?(?:required|needed)\b|\bworkshop\s+(?:is\s+)?not\s+(?:required|needed)\b|\b(?:does\s+not|doesn't|do\s+not|don't)\s+(?:require|need)\b"))return false;
            return Regex.IsMatch(text,@"\b(?:requires?|required|needs?|needed|prerequisites?)\s*:?\s*"+Noun)||
                Regex.IsMatch(text,@"\bworkshop\s+(?:(?:is|must\s+be|has\s+to\s+be|needs\s+to\s+be)\s+)?(?:required|needed|missing|a\s+prerequisite|completed|built)\b")||
                Regex.IsMatch(text,@"\b(?:cannot|can't|locked|unavailable)\b[^.!?]{0,60}\b(?:without|until)\s+"+Noun)||
                Regex.IsMatch(text,@"\b(?:build|complete|finish)\s+"+Noun+@"\s+(?:first|before)\b");
        }

        public static List<string> WorkshopExplanations(IEnumerable<string> texts) =>
            (texts??Enumerable.Empty<string>()).Where(Explanation)
                .Select(PresentationObservers.SemanticText).Distinct(StringComparer.OrdinalIgnoreCase).ToList();

        public static bool HasWorkshopExplanation(IEnumerable<string> texts) => WorkshopExplanations(texts).Count>0;

        // There is one concrete causal proposition in this trajectory. Wording,
        // enumeration order, markup, unrelated decoration and repeated copies
        // do not make an existing proposition a newly delivered explanation.
        public static bool HasNewWorkshopExplanation(IEnumerable<string> before,IEnumerable<string> after) =>
            !HasWorkshopExplanation(before)&&HasWorkshopExplanation(after);

        public static bool HasPersistentWorkshopExplanation(IEnumerable<string> before,IEnumerable<string> after) =>
            HasWorkshopExplanation(before)&&HasWorkshopExplanation(after);
    }
}
#endif

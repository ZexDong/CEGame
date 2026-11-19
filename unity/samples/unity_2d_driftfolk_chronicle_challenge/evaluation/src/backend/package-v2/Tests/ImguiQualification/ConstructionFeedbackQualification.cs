#if UNITY_EDITOR
using NUnit.Framework;
namespace GameCreate.Stormbound.Evaluator.ImguiQualification
{
    public sealed class ConstructionFeedbackQualification
    {
        [Test]public void F01_NewConcretePrerequisiteExplanationIsRecognized()
        {
            Assert.IsTrue(ConstructionFeedbackObservation.HasNewWorkshopExplanation(
                new[]{"Clinic","Workshop SITE"},new[]{"Clinic","A completed local Workshop is required."}));
        }
        [Test]public void F02_DecorationChangeWithBareWorkshopIsNotFeedback()
        {
            Assert.IsFalse(ConstructionFeedbackObservation.HasNewWorkshopExplanation(
                new[]{"Workshop","Decoration 1"},new[]{"Workshop","Decoration 2"}));
            Assert.IsFalse(ConstructionFeedbackObservation.HasPersistentWorkshopExplanation(
                new[]{"Workshop","Decoration 1"},new[]{"Workshop","Decoration 2"}));
        }
        [Test]public void F03_EnumerationOrderChangeIsNotANewExplanation()
        {
            Assert.IsFalse(ConstructionFeedbackObservation.HasNewWorkshopExplanation(
                new[]{"Workshop","Day 1","Clinic"},new[]{"Clinic","Workshop","Day 1"}));
            Assert.IsFalse(ConstructionFeedbackObservation.HasNewWorkshopExplanation(
                new[]{"Clinic requires a local Workshop","Day 1"},new[]{"Day 1","Clinic requires a local Workshop"}));
        }
        [Test]public void F04_PersistentConcreteRequirementIsALegalEquivalent()
        {
            var text=new[]{"Clinic [unbuilt] 0/3 work Cost 6 timber + 4 ore Requires: local Workshop; free slot"};
            Assert.IsTrue(ConstructionFeedbackObservation.HasPersistentWorkshopExplanation(text,text));
            Assert.IsFalse(ConstructionFeedbackObservation.HasNewWorkshopExplanation(text,text));
        }
        [Test]public void F05_BareNamesAndUnrelatedRequirementNeverExplainTheGuard()
        {
            Assert.IsFalse(ConstructionFeedbackObservation.HasWorkshopExplanation(new[]{"Workshop"}));
            Assert.IsFalse(ConstructionFeedbackObservation.HasWorkshopExplanation(new[]{"Requires food","Workshop"}));
            Assert.IsFalse(ConstructionFeedbackObservation.HasWorkshopExplanation(new[]{"Workshop","Need another passenger"}));
        }
        [Test]public void F06_NegatedWorkshopRequirementIsNotTheMissingPrerequisite()
        {
            foreach(var text in new[]{"No Workshop is required","Workshop is not required","Does not require a Workshop","We don't need a local Workshop"})
                Assert.IsFalse(ConstructionFeedbackObservation.HasWorkshopExplanation(new[]{text}),text);
        }
        [Test]public void F07_LegalCausalWordingVariantsAreAccepted()
        {
            foreach(var text in new[]{"Requires: local Workshop","Workshop required","Clinic locked until a local Workshop is completed","Cannot construct without a Workshop","Build a Workshop first"})
                Assert.IsTrue(ConstructionFeedbackObservation.HasWorkshopExplanation(new[]{text}),text);
        }
        [Test]public void F08_MarkupWhitespaceAndDecorationDoNotInventANewProposition()
        {
            var before=new[]{"Clinic requires <b>local Workshop</b>","Decoration 1"};
            var after=new[]{"Decoration 2","Clinic requires\nlocal Workshop"};
            Assert.IsTrue(ConstructionFeedbackObservation.HasPersistentWorkshopExplanation(before,after));
            Assert.IsFalse(ConstructionFeedbackObservation.HasNewWorkshopExplanation(before,after));
            Assert.IsFalse(ConstructionFeedbackObservation.HasNewWorkshopExplanation(
                new[]{"Needs Workshop"},new[]{"A completed local Workshop is required."}));
        }
    }
}
#endif

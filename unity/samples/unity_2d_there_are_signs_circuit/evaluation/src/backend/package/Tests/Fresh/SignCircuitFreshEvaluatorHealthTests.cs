using System;
using System.Collections;
using System.IO;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace OmniGame.Benchmark.SignCircuit.Evaluator
{
    [TestFixture]
    public sealed class SignCircuitFreshEvaluatorHealthTests
    {
        [UnityTest, Order(-1000)]
        public IEnumerator EVALUATOR_REGRESSION_FreshProcessHealth()
        {
            int firstFrame = Time.frameCount;
            yield return null;
            yield return null;
            Assert.That(Time.frameCount, Is.GreaterThan(firstFrame),
                "Fresh-process PlayMode frames did not advance.");

            string outputDirectory = ReadArgument("-signCircuitEvidenceOutput");
            Assert.That(string.IsNullOrWhiteSpace(outputDirectory), Is.False,
                "Fresh evaluator evidence output argument is missing.");
            string evaluationSessionId = ReadArgument("-signCircuitEvaluationSession");
            Assert.That(string.IsNullOrWhiteSpace(evaluationSessionId), Is.False,
                "Fresh evaluator session id is missing.");
            string nonce = Guid.NewGuid().ToString("N");
            const string evidenceId =
                "EVALUATOR_REGRESSION_FreshProcessHealth";
            SignCircuitEvidenceWriter.Write(evidenceId, new[]
            {
                "frame_advance=true",
                "fresh_process=true",
                "nonce=" + nonce
            });
            string path = Path.Combine(outputDirectory, evidenceId + ".json");
            Assert.That(File.Exists(path), Is.True,
                "Fresh evaluator evidence health record was not created.");
            string roundTrip = File.ReadAllText(path);
            Assert.That(roundTrip, Does.Contain(nonce),
                "Fresh evaluator evidence health record did not round-trip through storage.");
        }

        static string ReadArgument(string key)
        {
            string[] args = Environment.GetCommandLineArgs();
            for (int index = 0; index < args.Length - 1; index++)
            {
                if (string.Equals(args[index], key,
                        StringComparison.OrdinalIgnoreCase))
                {
                    return args[index + 1].Trim('"');
                }
            }
            return string.Empty;
        }
    }
}

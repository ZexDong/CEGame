using System;using System.IO;using System.Linq;using System.Collections;using NUnit.Framework;using UnityEngine;
public class EvaluationEvidenceTests {
 [Serializable] public class Row{public string id,state;}
 [Serializable] public class Report{public Row[] leaves;}
 static Report Read()=>JsonUtility.FromJson<Report>(File.ReadAllText(Environment.GetEnvironmentVariable("GAMECREATE_EVIDENCE_FILE")));
 public static IEnumerable Cases(){foreach(var row in Read().leaves)yield return new TestCaseData(row.id).SetName(row.id);}
 [TestCaseSource(nameof(Cases))] public void Checkpoint(string id){
  var row=Read().leaves.Single(x=>x.id==id);
  if(row.state=="INCONCLUSIVE_EVALUATOR")Assert.Inconclusive("Evaluator could not establish reliable evidence.");
  Assert.That(row.state,Is.EqualTo("PASS"),"Evidence state: "+row.state);
 }
}

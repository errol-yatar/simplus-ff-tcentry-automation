global class ProcessCaseTimeEntryLogScheduler implements Schedulable {
   global void execute(SchedulableContext sc) {
      ProcessCaseTimeEntryLogBatch b = new ProcessCaseTimeEntryLogBatch(); 
      Database.executebatch(b, 50);
   }
}
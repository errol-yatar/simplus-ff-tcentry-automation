/***************************************************
Class Name: 			ProcessCaseTimeEntryLogBatch
Account/Project Name: 	Simplus Timecard
Description: 			Processes all the unprocessed Case Time Entry Logs
Date Created: 			09.SEP.2018
Author : 				Errol John Yatar

Revision History:
Version	Author			Date				Detail              Code Reviewed?
Errol Yatar				09.SEP.2018			Intial creation.    No

***************************************************/
global class ProcessCaseTimeEntryLogBatch implements Database.Batchable<sObject>, Database.Stateful {

    private Date referenceDate;
    
    // Variables for batch logging
    global Batch_Run__c br;

    // Store the current day here
    global Integer dayOfWeek = 0; // 0 is Monday, 1 is Tuesday, 2 is Wednesday so forth and so on..

    global final List<String> dayOfWeekStr = new List<String>{'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'};

    //We need to check if this the first batch of the job, so we won't do unnecessary resets.
    global Boolean isFirstBatch = true;


    // Default constructor
    global ProcessCaseTimeEntryLogBatch() {
        this.referenceDate = Date.today();
    }

    // Constructor with day of week parameter, used in daisy chain
    global ProcessCaseTimeEntryLogBatch(Integer dayOfWeek) {
        this.referenceDate = Date.today();
        this.dayOfWeek = dayOfWeek;
    }

    // Constructor with reference date. Use this if you want to process time entries from a specific week.
    global ProcessCaseTimeEntryLogBatch(Date referenceDate) {
        this.referenceDate = referenceDate;
    }
	
	global Database.QueryLocator start(Database.BatchableContext bc) {
        // Initialize the Batch Run record
        br = new Batch_Run__c();
        br.Execution_Date_Time__c = DateTime.now();
        br.Debug_Messages__c = '';
        br.Records_Processed__c = 0;
        br.No_of_Errors__c = 0;
        br.Number_of_Batches__c = 0;
        br.Number_of_Successful_Batches__c = 0;

        // Calculate the monday and sunday dates of the reference date's week.
        Integer dateDiff = Date.newInstance(1900,1,7).daysBetween(referenceDate);
        Date mondayDate = referenceDate - Integer.valueOf(Math.mod(dateDiff,7));
        mondayDate = mondayDate.addDays(1);
        Date sundayDate = mondayDate.addDays(6);
        Date currentDate = mondayDate.addDays(dayOfWeek);
        br.Debug_Messages__c += ('mondayDate: ' + mondayDate + '\n');
        br.Debug_Messages__c += ('sundayDate: ' + sundayDate + '\n');
        br.Debug_Messages__c += 'Processing ' + dayOfWeekStr[dayOfWeek] + ' job of the week.\n';

        // Include users only in the timecard automation group.
        Set<Id> usersId = new Set<Id>();
        Set<Id> groupIds = new Set<Id>();
        for(GroupMember gm : [SELECT Id, UserOrGroupId FROM GroupMember WHERE Group.DeveloperName = 'Timecard_Automation_Users']) {
            // If the group member is a group,
            if(String.valueOf(gm.UserOrGroupId).startsWith('00G')) {
                groupIds.add(gm.UserOrGroupId);
            }
            usersId.add(gm.UserOrGroupId);
        }

        if(!groupIds.isEmpty()) {
            for(GroupMember gm : [SELECT Id, UserOrGroupId FROM GroupMember WHERE Id IN :groupIds]) {
                if(String.valueOf(gm.UserOrGroupId).startsWith('005')) {
                    usersId.add(gm.UserOrGroupId);
                }
            }
        }

		String query = 'SELECT Id, ' +
						'	CreatedById, ' +
						'	Project_ctl__c, ' +
						'	Resource_ctl__c, ' +
						'	Resource_ctl__r.pse__Salesforce_User__c, ' +
                        '   Resource_ctl__r.Name, ' +
						'	Assignment_ctl__c, ' +
						'	Case_ctl__c, ' +
						'	Case_ctl__r.CaseNumber, ' +
						'	Comments_ctl__c, ' +
						'	Day_of_the_Week_ctl__c, ' +
						'	StartDateFormula_ctl__c, ' +
						'	EndDateFormula_ctl__c, ' +
						'	Task_Type_ctl__c, ' +
						'	Parent_Case_Time_Entry__r.Project_Task__r.Name, ' +
						'	Time_Spent_ctl__c, ' +
						'	Task_Date__c, ' +
						'	Case_Comment_Created__c ' +
						'FROM Case_Time_Entry_Log__c ' +
						'WHERE StartDateFormula_ctl__c = :mondayDate ' +
                        '   AND EndDateFormula_ctl__c = :sundayDate' + 
                        '   AND Resource_ctl__r.pse__Salesforce_User__c IN :usersId' + 
                        '   AND Task_Date__c = :currentDate' + 
                        '   AND Parent_Case_Time_Entry__r.Exclude_from_Time_Entry_Automation__c = false';
		return Database.getQueryLocator(query);
	}

   	global void execute(Database.BatchableContext bc, List<Case_Time_Entry_Log__c> scope) {
        br.Records_Processed__c += scope.size();
        br.Number_of_Batches__c += 1;

        br.Debug_Messages__c += 'isFirstBatch: ' + isFirstBatch + '\n';

        // Create a list of Case Time Entry Logs to be updated later
        List<Case_Time_Entry_Log__c> cteLogToUpdate = new List<Case_Time_Entry_Log__c>();
        List<CaseComment> caseCommentList = new List<CaseComment>();

        // Retrieve existing timecard records.
        // The existing timecard records are mapped with Assignment Id/Start Date/End Date as a key.
        Set<Id> assignmentIds = new Set<Id>();
        Set<Date> startDates = new Set<Date>();
        Set<Date> endDates = new Set<Date>();
        for(Case_Time_Entry_Log__c cteLog : scope) {
            assignmentIds.add(cteLog.Assignment_ctl__c);
            startDates.add(cteLog.StartDateFormula_ctl__c);
            endDates.add(cteLog.EndDateFormula_ctl__c);
        }
        Map<String, pse__Timecard_Header__c> mapExistingTimecards = new Map<String, pse__Timecard_Header__c>();
        for(pse__Timecard_Header__c tc : [SELECT Id, 
                                            pse__Assignment__c,
                                            pse__Start_Date__c, 
                                            pse__End_Date__c,
                                            pse__Sunday_Notes__c,
                                            pse__Monday_Notes__c,
                                            pse__Tuesday_Notes__c,
                                            pse__Wednesday_Notes__c,
                                            pse__Thursday_Notes__c,
                                            pse__Friday_Notes__c,
                                            pse__Saturday_Notes__c,
                                            pse__Sunday_Hours__c,
                                            pse__Monday_Hours__c,
                                            pse__Tuesday_Hours__c,
                                            pse__Wednesday_Hours__c,
                                            pse__Thursday_Hours__c,
                                            pse__Friday_Hours__c,
                                            pse__Saturday_Hours__c
                                        FROM pse__Timecard_Header__c 
                                        WHERE pse__Assignment__c IN :assignmentIds 
                                            AND pse__Start_Date__c IN :startDates
                                            AND pse__End_Date__c IN :endDates
                                            AND Practice__c LIKE 'Managed%Services']) {
            //Reset the timecard header hours and comments to cater the updates regarding the case time entries
            if(isFirstBatch == true) {
                tc.put('pse__' + dayOfWeekStr[dayOfWeek] + '_Notes__c', '');
            }
            br.Debug_Messages__c += 'current notes: ' + tc.get('pse__' + dayOfWeekStr[dayOfWeek] + '_Notes__c') + '\n';
            mapExistingTimecards.put('' + tc.pse__Assignment__c + tc.pse__Start_Date__c.format() + tc.pse__End_Date__c.format(), tc);
        }

        // Create a map of case time entry log records to the timecard record to be inserted.
        // This will come in handy when we create the Task Time later.
        Set<Id> projectIds = new Set<Id>(); //This will be used later when we retrieve the project tasks.
        for(Case_Time_Entry_Log__c cteLog : scope) {
            br.Debug_Messages__c += 'processing time entry log: ' + cteLog.Id + '\n';
            // Create the timecard record using the values from the case time entry log.
            pse__Timecard_Header__c tc;
            // Check if there is an existing timecard header for that assignment for that week.
            String key = cteLog.Assignment_ctl__c + cteLog.StartDateFormula_ctl__c.format() + cteLog.EndDateFormula_ctl__c.format();
            if(mapExistingTimecards.containsKey(key)) {
                tc = mapExistingTimecards.get(key);
            }
            // If the timecard header is non-existing, this time we will create a new one.
            else {
                tc = new pse__Timecard_Header__c(
                    OwnerId = cteLog.CreatedById, 
                    pse__Resource__c = cteLog.Resource_ctl__c,
                    pse__Project__c = cteLog.Project_ctl__c,
                    pse__Assignment__c = cteLog.Assignment_ctl__c,
                    pse__Start_Date__c = cteLog.StartDateFormula_ctl__c,
                    pse__End_Date__c = cteLog.EndDateFormula_ctl__c,
                    pse__Status__c = 'Saved',
                    pse__Sunday_Hours__c = 0,
                    pse__Sunday_Notes__c = '',
                    pse__Monday_Hours__c = 0,
                    pse__Monday_Notes__c = '',
                    pse__Tuesday_Hours__c = 0,
                    pse__Tuesday_Notes__c = '',
                    pse__Wednesday_Hours__c = 0,
                    pse__Wednesday_Notes__c = '',
                    pse__Thursday_Hours__c = 0,
                    pse__Thursday_Notes__c = '',
                    pse__Friday_Hours__c = 0,
                    pse__Friday_Notes__c = '',
                    pse__Saturday_Hours__c = 0,
                    pse__Saturday_Notes__c = ''
                );
                // and put it in the map
                mapExistingTimecards.put(key, tc);
            }

            // Compose the notes that will be appended to the daily notes field. The format will be '[CaseNumber] Task notes (hours spent)'
            // Each cases will be separated by a bar '|' character.
            String taskComment = '[' + Integer.valueOf(cteLog.Case_ctl__r.CaseNumber) + '] ' + cteLog.Comments_ctl__c + ' (' + cteLog.Time_Spent_ctl__c + 'h)';

            // Compose the case comment body just in case the character limit is reached. 
            String caseCommentBody = 'Case time entry note: ' + cteLog.Comments_ctl__c  + '\n'
                + 'Resource: ' + cteLog.Resource_ctl__r.Name + '\n'
                + 'Time Spent: ' + cteLog.Time_Spent_ctl__c + 'h\n'
                + 'Task Date: ' + cteLog.Task_Date__c.format() + '\n'
                + 'Task Type: ' + cteLog.Parent_Case_Time_Entry__r.Project_Task__r.Name;
            CaseComment cmt = new CaseComment(
                ParentId = cteLog.Case_ctl__c,
                CommentBody = caseCommentBody
            ); // this will be added at a later code

            // Fill in the hours and notes depending on what day the case time entry log is
            String limitMessage = Label.TCAuto_CharLimitMsg;
            tc.put('pse__' + cteLog.Day_of_the_Week_ctl__c + '_Hours__c', Double.valueOf(tc.get('pse__' + cteLog.Day_of_the_Week_ctl__c + '_Hours__c')) + cteLog.Time_Spent_ctl__c);
            String combinedString = (String.isEmpty(String.valueOf(tc.get('pse__' + cteLog.Day_of_the_Week_ctl__c + '_Notes__c'))) 
                                        ? '' 
                                        : (tc.get('pse__' + cteLog.Day_of_the_Week_ctl__c + '_Notes__c') + ' | ')) + taskComment;
            if(combinedString.length() > 255 || tc.get('pse__' + cteLog.Day_of_the_Week_ctl__c + '_Notes__c') == limitMessage) {
                // Create a case comment instead of appending to task notes
                if(!cteLog.Case_Comment_Created__c) {
                    caseCommentList.add(cmt);
                    cteLog.Case_Comment_Created__c = true;
                    cteLogToUpdate.add(cteLog);
                }
                if(String.isEmpty(String.valueOf(tc.get('pse__' + cteLog.Day_of_the_Week_ctl__c + '_Notes__c')))) {
                    tc.put('pse__' + cteLog.Day_of_the_Week_ctl__c + '_Notes__c', limitMessage);
                }
            }
            else {
                tc.put('pse__' + cteLog.Day_of_the_Week_ctl__c + '_Notes__c', combinedString);
            }
            
            projectIds.add(cteLog.Project_ctl__c);
        }

        // Upsert the timecard records.
        br.Debug_Messages__c += 'Existing timecards size: ' + mapExistingTimecards.size() + '\n';
        if(mapExistingTimecards.values().size() > 0) {
            // upsert mapExistingTaskTimes.values();
            // DML statement
            Database.UpsertResult[] srList = Database.upsert(mapExistingTimecards.values(), false);

            // Iterate through each returned result
            Integer idx = 0;
            for (Database.UpsertResult sr : srList) {
                if (!sr.isSuccess()) {
                    // Operation failed, so get all errors                
                    for(Database.Error err : sr.getErrors()) {
                        br.No_of_Errors__c += 1;
                        br.Debug_Messages__c += 'The following error has occurred.\n';
                        br.Debug_Messages__c += err.getStatusCode() + ': ' + err.getMessage() + '\n';
                        br.Debug_Messages__c += 'Error Location: Database.upsert(mapExistingTimecards.values());\n';
                        br.Debug_Messages__c += 'Failed Timecard Header record info:\n';
                        br.Debug_Messages__c += JSON.serialize(mapExistingTimecards.values().get(idx)) + '\n';
                    }
                }
                idx += 1;
            }
        }

        // First, we should retrieve the project tasks for each time card entry log project.
        // We'll use the projectIds collection we created earlier.
        // The inner map has the project task id as a key.
        Map<Id, Map<Id, pse__Project_Task__c>> mapProjTaskData = new Map<Id, Map<Id, pse__Project_Task__c>>();

        for(pse__Project_Task__c pt : [SELECT Id, Name, pse__Project__c FROM pse__Project_Task__c WHERE pse__Project__c IN :projectIds]) {
            if(!mapProjTaskData.containsKey(pt.pse__Project__c)) {
                mapProjTaskData.put(pt.pse__Project__c, new Map<Id, pse__Project_Task__c>());
            }
            if(!mapProjTaskData.get(pt.pse__Project__c).containsKey(pt.Id)) {
                mapProjTaskData.get(pt.pse__Project__c).put(pt.Id, pt);
            }
        }

        // Now, we can create the timecard task time records using the map we created earlier.
        // First, we should retrieve existing timecard task time records.
        // The existing timecard task time records are mapped with 'Assignment Id + Start Date + Project Type Id' as a key.
        Set<Date> tt_startDates = new Set<Date>();
        Set<Id> taskTypes = new Set<Id>();
        for(Case_Time_Entry_Log__c cteLog : scope) {
            if(mapProjTaskData.get(cteLog.Project_ctl__c) != null) {
                // Okay this is hard to explain
                // but basically what we're doing here, we will add all the id of all the task types of the project
                taskTypes.addAll(mapProjTaskData.get(cteLog.Project_ctl__c).keySet());
            }
            tt_startDates.add(cteLog.StartDateFormula_ctl__c);
        }
        Map<String, pse__Task_Time__c> mapExistingTaskTimes = new Map<String, pse__Task_Time__c>();
        for(pse__Task_Time__c tt : [SELECT Id, 
                                        pse__Timecard__c,
                                        pse__Start_Date__c, 
                                        pse__Project_Task__c,
                                        pse__Sunday_Hours__c,
                                        pse__Monday_Hours__c,
                                        pse__Tuesday_Hours__c,
                                        pse__Wednesday_Hours__c,
                                        pse__Thursday_Hours__c,
                                        pse__Friday_Hours__c,
                                        pse__Saturday_Hours__c,
                                        pse__Timecard__r.pse__Assignment__c
                                    FROM pse__Task_Time__c 
                                    WHERE pse__Project_Task__c IN :taskTypes 
                                        AND pse__Start_Date__c IN :tt_startDates
                                        AND pse__Timecard__c IN :mapExistingTimecards.values()]) {
            //Reset the task time hours and comments to cater the updates regarding the case time entries
            if(isFirstBatch == true) {
                tt.put('pse__' + dayOfWeekStr[dayOfWeek] + '_Hours__c', 0);
            }
            br.Debug_Messages__c += 'current hours: ' + tt.get('pse__' + dayOfWeekStr[dayOfWeek] + '_Hours__c') + '\n';
            mapExistingTaskTimes.put('' + tt.pse__Timecard__r.pse__Assignment__c + tt.pse__Start_Date__c.format() + tt.pse__Project_Task__c, tt);
        }

        for(Case_Time_Entry_Log__c cteLog : scope) {
            // From the map we created earlier, we can determine the timecard record we will attach this task time record to
            // using the case time entry combinations of values from case time entries as key
            String tch_key = '' + cteLog.Assignment_ctl__c + cteLog.StartDateFormula_ctl__c.format() + cteLog.EndDateFormula_ctl__c.format();

            // Check if the key fits inside the keyhole
            if (!mapExistingTimecards.containsKey(tch_key) || mapExistingTimecards.get(tch_key) == null) {
                br.No_of_Errors__c += 1;
                br.Debug_Messages__c += 'No timecard header found for this case time entry log record: \n';
                br.Debug_Messages__c += JSON.serialize(cteLog) + '\n';
                continue;
            }

            // Create the task time record using the values from the case time entry log.
            pse__Task_Time__c tt = null;
            // Key: 'Assignment Id + Start Date + Project Type Id' as a key.
            String tt_key = '' + cteLog.Assignment_ctl__c + cteLog.StartDateFormula_ctl__c.format() + cteLog.Task_Type_ctl__c;
            if(mapExistingTaskTimes.containsKey(tt_key)) {
                tt = mapExistingTaskTimes.get(tt_key);
            }
            else {
                tt = new pse__Task_Time__c(
                    pse__Start_Date__c = cteLog.StartDateFormula_ctl__c,
                    pse__Sunday_Hours__c = 0,
                    pse__Sunday_Notes__c = '',
                    pse__Monday_Hours__c = 0,
                    pse__Monday_Notes__c = '',
                    pse__Tuesday_Hours__c = 0,
                    pse__Tuesday_Notes__c = '',
                    pse__Wednesday_Hours__c = 0,
                    pse__Wednesday_Notes__c = '',
                    pse__Thursday_Hours__c = 0,
                    pse__Thursday_Notes__c = '',
                    pse__Friday_Hours__c = 0,
                    pse__Friday_Notes__c = '',
                    pse__Saturday_Hours__c = 0,
                    pse__Saturday_Notes__c = ''
                );
                mapExistingTaskTimes.put(tt_key, tt);
            }

            if(cteLog.Task_Type_ctl__c == null) {
                // This means that there is no task type of that name found in the project's task types.
                cteLog.Batch_Fail_Reason__c = 'The task type with Id \'' + cteLog.Task_Type_ctl__c + '\' is not present for this record\'s project.';
            }
            else {
                // Master detail fields are not writeable if we cannot reparent the record that is already inserted.
                // that's why we have this null check for the Id, meaning if the record is not yet inserted
                if(tt.Id == null) {                    
                    tt.pse__Timecard__c = mapExistingTimecards.get(tch_key).Id;
                }

                // Set the project task to the matching project task id.
                if(tt.pse__Project_Task__c == null) {
                    tt.pse__Project_Task__c = cteLog.Task_Type_ctl__c;
                }

                // Fill in the hours and notes depending on what day the case time entry log is
                String hoursField = 'pse__' + dayOfWeekStr[dayOfWeek] + '_Hours__c';
                tt.put(hoursField, Double.valueOf(tt.get(hoursField)) + cteLog.Time_Spent_ctl__c);
            }
        }

        br.Debug_Messages__c += 'Existing task times size: ' + mapExistingTaskTimes.size() + '\n';
        // Upsert the created/retrieved task time records, if there's any
        if(mapExistingTaskTimes.values().size() > 0) {
            // upsert mapExistingTaskTimes.values();
            // DML statement
            Database.UpsertResult[] srList = Database.upsert(mapExistingTaskTimes.values(), false);

            // Iterate through each returned result
            Integer idx = 0;
            for (Database.UpsertResult sr : srList) {
                if (!sr.isSuccess()) {
                    // Operation failed, so get all errors                
                    for(Database.Error err : sr.getErrors()) {
                        br.No_of_Errors__c += 1;
                        br.Debug_Messages__c += 'The following error has occurred.\n';
                        br.Debug_Messages__c += err.getStatusCode() + ': ' + err.getMessage() + '\n';
                        br.Debug_Messages__c += 'Error Location: Database.upsert(mapExistingTaskTimes.values());\n';
                        br.Debug_Messages__c += 'Failed Task Time record info:\n';
                        br.Debug_Messages__c += JSON.serialize(mapExistingTaskTimes.values().get(idx)) + '\n';
                    }
                }
                idx += 1;
            }
        }

        // Insert the case comments, if there's any
        if(caseCommentList.size() > 0) {
            // insert caseCommentList;
            // DML statement
            Database.SaveResult[] srList = Database.insert(caseCommentList, false);

            // Iterate through each returned result
            for (Database.SaveResult sr : srList) {
                if (!sr.isSuccess()) {
                    // Operation failed, so get all errors                
                    for(Database.Error err : sr.getErrors()) {
                        br.No_of_Errors__c += 1;
                        br.Debug_Messages__c += 'The following error has occurred.\n';
                        br.Debug_Messages__c += err.getStatusCode() + ': ' + err.getMessage() + '\n';
                        br.Debug_Messages__c += 'Error Location: Database.insert(caseCommentList);\n';
                    }
                }
            }
        }

        if(cteLogToUpdate.size() > 0) {
            // update cteLogToUpdate;
            // DML statement
            Database.SaveResult[] srList = Database.update(cteLogToUpdate, false);

            // Iterate through each returned result
            for (Database.SaveResult sr : srList) {
                if (!sr.isSuccess()) {
                    // Operation failed, so get all errors                
                    for(Database.Error err : sr.getErrors()) {
                        br.No_of_Errors__c += 1;
                        br.Debug_Messages__c += 'The following error has occurred.\n';
                        br.Debug_Messages__c += err.getStatusCode() + ': ' + err.getMessage() + '\n';
                        br.Debug_Messages__c += 'Error Location: Database.update(cteLogToUpdate);\n';
                    }
                }
            }
        }

        // Please try to make this line of code at the most bottom part possible
        br.Number_of_Successful_Batches__c += 1;

        // Set isFirstBatch to false so that the hours and notes doesn't reset
        isFirstBatch = false;
	}
	
	global void finish(Database.BatchableContext bc) {
		// Finalize and insert the batch run record.
        br.Execution_Finished_Time__c = DateTime.now();
        System.debug(br);
        insert br;

        // Execute the batch for the next day if it is not Friday yet
        if (dayOfWeek < 4 && !Test.isRunningTest()) {
            Database.executeBatch(new ProcessCaseTimeEntryLogBatch(dayOfWeek + 1), 50);
        }
	}
	
}
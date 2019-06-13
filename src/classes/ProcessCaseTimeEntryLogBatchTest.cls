@isTest
public class ProcessCaseTimeEntryLogBatchTest {
	
	@testSetup
	public static void testPreparation(){
		User u;
        System.runAs(new User(Id = UserInfo.getUserId())){
            u = (User) TestFactory.createSObject(new User(
				LastName = 'Resource A',
				UserRoleId = [SELECT Id FROM UserRole WHERE Name = 'Consultant' LIMIT 1].Id,
				ProfileId = [SELECT Id FROM Profile WHERE Name = 'Consultant (S)' LIMIT 1].Id,
				Username = 'testUserA@simplus.com',
				CommunityNickname = 'ResourceA'
			)); // User with valid assignment

			insert u;
			
			GroupMember gm = new GroupMember(
				UserOrGroupId = u.Id,
				GroupId = [SELECT Id FROM Group WHERE DeveloperName = 'Timecard_Automation_Users' LIMIT 1].Id
			);

			insert gm;

        }
		
		insert new Trigger_Controls__c(Case_Time_Entry_Trigger__c = true, Recurring_Revenue_Renewal_Opp__c = true);

		// Create Region
		pse__Region__c region = (pse__Region__c) TestFactory.createSObject(new pse__Region__c(), true);

		// Create Practice Records
        pse__Grp__c g = (pse__Grp__c) TestFactory.createSObject(new pse__Grp__c(), true);

		pse__Practice__c practice = (pse__Practice__c) TestFactory.createSObject(new pse__Practice__c(Name = 'Managed Services'), true);
        
        
        pse__Permission_Control__c pc = (pse__Permission_Control__c) TestFactory.createSObject(new pse__Permission_Control__c(pse__Region__c = region.Id), true);

		// Create resource record for the current running user
		
        Contact c = (Contact)TestFactory.createSObject(new Contact(pse__Allow_Timecards_Without_Assignment__c = true,
																	pse__Practice__c = practice.Id, pse__Region__c = region.Id, 
                                                                   pse__Is_Resource_Active__c = true, pse__Is_Resource__c = true,
                                                                  Revenue_Groups__c = 'Manager', pse__Salesforce_User__c = UserInfo.getUserId()), true);
		
		// Create Account
		Account acct = (Account) TestFactory.createSObject(new Account());

		insert acct;

		// Create Project
		pse__Proj__c proj = (pse__Proj__c) TestFactory.createSObject(new pse__Proj__c(
			pse__Account__c = acct.Id,
			pse__Region__c = region.Id,
			pse__Practice__c = practice.Id
		), true);

		// Create Project Tasks
		List<pse__Project_Task__c> projTasks = new List<pse__Project_Task__c>();

		projTasks.add(
			(pse__Project_Task__c) TestFactory.createSObject(new pse__Project_Task__c(
				Name = 'Customer Readiness',
				pse__Project__c = proj.Id)
			)
		);

		projTasks.add(
			(pse__Project_Task__c) TestFactory.createSObject(new pse__Project_Task__c(
				Name = 'Service Delivery',
				pse__Project__c = proj.Id)
			)
		);

		insert projTasks;

		// Create a Work Calendar record
		pse__Work_Calendar__c workCalendar = (pse__Work_Calendar__c) TestFactory.createSObject(new pse__Work_Calendar__c(), true);

		// Create a Resource Records
		Contact resourceA = (Contact) TestFactory.createSObject(new Contact(
			AccountId = acct.Id,
			pse__Salesforce_User__c = u.Id,
			pse__Region__c = region.Id,
			pse__Is_Resource__c = true,
			pse__Is_Resource_Active__c = true,
			pse__Work_Calendar__c = workCalendar.Id,
			pse__Group__c = g.Id,
			RecordTypeId = SObjectType.Contact.getRecordTypeInfosByDeveloperName().get('PSA_Resource').getRecordTypeId(),
			LastName = 'Resource A',
			pse__Practice__c = practice.Id
		), true); // Valid resource

		// Create a Project Assignment Schedule
		pse__Schedule__c schedA = (pse__Schedule__c) TestFactory.createSObject(new pse__Schedule__c(pse__Start_Date__c = Date.today().addDays(-7), 
																								pse__End_Date__c = Date.today().addDays(30)), true);

		pse__Assignment__c assignA = (pse__Assignment__c)TestFactory.createSObject(new pse__Assignment__c(pse__Is_Billable__c = true, pse__Resource__c = resourceA.Id, 
                                                                                                     pse__Schedule__c = schedA.Id, Product_Family__c = 'Salesforce', pse__Role__c = 'Developer', 
                                                                                                     pse__Project__c = proj.Id, pse__Bill_Rate__c = 300), true);

		// Create a case
		Case caseA = (Case) TestFactory.createSObject(new Case(
			Subject = 'Case A',
			AccountId = acct.Id,
			Project__c = proj.Id
		), true);
	}

	@isTest
	public static void testBatch() {
		Case caseA = [SELECT Id, Project__c FROM Case WHERE Subject = 'Case A' LIMIT 1];

		User resource = [SELECT Id FROM User WHERE LastName = 'Resource A' LIMIT 1];

		Integer dateDiff = Date.newInstance(1900,1,7).daysBetween(Date.today());
        Date mondayDate = Date.today() - Integer.valueOf(Math.mod(dateDiff,7));
		mondayDate = mondayDate.addDays(1);

		Map<String, pse__Project_Task__c> projectTasksMap = getProjectTasks(caseA.Project__c);
		Id serviceDelivery = projectTasksMap.get('Service Delivery').Id;
		Id customerReadiness = projectTasksMap.get('Customer Readiness').Id;


		Test.startTest();
		System.runAs(resource) {
			List<Case_Time_Entry__c> cteList = new List<Case_Time_Entry__c>();
			for(Integer i = 0; i < 7; i++) {
				Case_Time_Entry__c cte = new Case_Time_Entry__c(
					Case__c = caseA.Id,
					Comments__c = 'Test Comment ' + i,
					Date__c = mondayDate.addDays(i),
					Project_Task__c = serviceDelivery,
					Source__c = 'Visualforce',
					Time_Spent__c = 5.00
				);

				cteList.add(cte);

				Case_Time_Entry__c cte2 = new Case_Time_Entry__c(
					Case__c = caseA.Id,
					Comments__c = 'Test Comment ' + i,
					Date__c = mondayDate.addDays(i),
					Project_Task__c = customerReadiness,
					Source__c = 'Visualforce',
					Time_Spent__c = 5.00
				);

				cteList.add(cte2);
			}

			insert cteList;
		}
		Database.executeBatch(new ProcessCaseTimeEntryLogBatch());
		Test.stopTest();
	}

    @isTest
	public static void testBatchBulk() {
		Case caseA = [SELECT Id, Project__c FROM Case WHERE Subject = 'Case A' LIMIT 1];

		User resource = [SELECT Id FROM User WHERE LastName = 'Resource A' LIMIT 1];

		Integer dateDiff = Date.newInstance(1900,1,7).daysBetween(Date.today());
        Date mondayDate = Date.today() - Integer.valueOf(Math.mod(dateDiff,7));
		mondayDate = mondayDate.addDays(1);

		Map<String, pse__Project_Task__c> projectTasksMap = getProjectTasks(caseA.Project__c);
		Id serviceDelivery = projectTasksMap.get('Service Delivery').Id;
		Id customerReadiness = projectTasksMap.get('Customer Readiness').Id;

		Test.startTest();
		System.runAs(resource) {
			List<Case_Time_Entry__c> cteList = new List<Case_Time_Entry__c>();
			for(Integer i = 0; i < 7; i++) {
				Case_Time_Entry__c cte = new Case_Time_Entry__c(
					Case__c = caseA.Id,
					Comments__c = 'Test Comment ' + i,
					Date__c = mondayDate.addDays(i),
					Project_Task__c = serviceDelivery,
					Source__c = 'Visualforce',
					Time_Spent__c = 5.00
				);

				cteList.add(cte);

				Case_Time_Entry__c cte2 = new Case_Time_Entry__c(
					Case__c = caseA.Id,
					Comments__c = 'Test Comment ' + i,
					Date__c = mondayDate.addDays(i),
					Project_Task__c = customerReadiness,
					Source__c = 'Visualforce',
					Time_Spent__c = 5.00
				);

				cteList.add(cte2);
			}

			insert cteList;
		}

		Database.executeBatch(new ProcessCaseTimeEntryLogBatch(), 50);
		Test.stopTest();
	}

	@isTest
	public static void testBatch2() {
		Case caseA = [SELECT Id, Project__c FROM Case WHERE Subject = 'Case A' LIMIT 1];

		User resource = [SELECT Id FROM User WHERE LastName = 'Resource A' LIMIT 1];

		Integer dateDiff = Date.newInstance(1900,1,7).daysBetween(Date.today());
        Date mondayDate = Date.today() - Integer.valueOf(Math.mod(dateDiff,7));
		mondayDate = mondayDate.addDays(1);

		Map<String, pse__Project_Task__c> projectTasksMap = getProjectTasks(caseA.Project__c);
		Id serviceDelivery = projectTasksMap.get('Service Delivery').Id;
		Id customerReadiness = projectTasksMap.get('Customer Readiness').Id;

		Test.startTest();
		System.runAs(resource) {
			List<Case_Time_Entry__c> cteList = new List<Case_Time_Entry__c>();
			for(Integer i = 0; i < 7; i++) {
				Case_Time_Entry__c cte = new Case_Time_Entry__c(
					Case__c = caseA.Id,
					Comments__c = 'Test Comment ' + i,
					Date__c = mondayDate.addDays(i),
					Project_Task__c = serviceDelivery,
					Source__c = 'Visualforce',
					Time_Spent__c = 5.00
				);

				cteList.add(cte);

				Case_Time_Entry__c cte2 = new Case_Time_Entry__c(
					Case__c = caseA.Id,
					Comments__c = 'Test Comment ' + i,
					Date__c = mondayDate.addDays(i),
					Project_Task__c = customerReadiness,
					Source__c = 'Visualforce',
					Time_Spent__c = 5.00
				);

				cteList.add(cte2);
			}

			insert cteList;
		}

		Database.executeBatch(new ProcessCaseTimeEntryLogBatch(Date.today()));
		Test.stopTest();
	}

	@isTest
	public static void testBatchExistingTimecards() {
		User u = [SELECT Id FROM User WHERE LastName = 'Resource A'];
		Contact res = [SELECT Id FROM Contact WHERE pse__Salesforce_User__c = :u.Id];
		pse__Assignment__c assign = [SELECT Id, pse__Project__c FROM pse__Assignment__c WHERE pse__Resource__c = :res.Id];
		Case caseA = [SELECT Id, Project__c FROM Case WHERE Subject = 'Case A'];

		Integer dateDiff = Date.newInstance(1900,1,7).daysBetween(Date.today());
        Date mondayDate = Date.today() - Integer.valueOf(Math.mod(dateDiff,7));
		mondayDate = mondayDate.addDays(1);

		Test.startTest();
		pse__Timecard_Header__c tch = new pse__Timecard_Header__c(
			OwnerId = u.Id,
			pse__Resource__c = res.Id,
			pse__Project__c = assign.pse__Project__c,
			pse__Assignment__c = assign.Id,
			pse__Start_Date__c = mondayDate,
			pse__End_Date__c = mondayDate.addDays(6),
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

		insert tch;

		pse__Task_Time__c tt = new pse__Task_Time__c(
			pse__Start_Date__c = mondayDate,
			pse__Project_Task__c = getProjectTasks(assign.pse__Project__c).get('Service Delivery').Id,
			pse__Timecard__c = tch.Id,
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

		insert tt;
		System.runAs(u) {
			List<Case_Time_Entry__c> cteList = new List<Case_Time_Entry__c>();
			for(Integer i = 0; i < 7; i++) {
				Case_Time_Entry__c cte = new Case_Time_Entry__c(
					Case__c = caseA.Id,
					Comments__c = 'Test Comment long case comment long case comment long case comment long case comment' + 
						' long case comment long case comment long case comment long case comment long case comment' + 
						' long case comment long case comment long case comment long case comment long c' + i,
					Date__c = mondayDate.addDays(i),
					Project_Task__c = getProjectTasks(caseA.Project__c).get('Service Delivery').Id,
					Source__c = 'Visualforce',
					Time_Spent__c = 5.00
				);

				cteList.add(cte);

				Case_Time_Entry__c cte2 = new Case_Time_Entry__c(
					Case__c = caseA.Id,
					Comments__c = 'Test Comment long case comment long case comment long case comment long case comment' + 
						' long case comment long case comment long case comment long case comment long case comment' + 
						' long case comment long case comment long case comment long case comment long c' + i,
					Date__c = mondayDate.addDays(i),
					Project_Task__c = getProjectTasks(caseA.Project__c).get('Customer Readiness').Id,
					Source__c = 'Visualforce',
					Time_Spent__c = 5.00
				);

				cteList.add(cte2);
			}

			insert cteList;
		}

		Database.executeBatch(new ProcessCaseTimeEntryLogBatch(Date.today()));
		Test.stopTest();
	}

	@isTest
	public static void testScheduleableJob() {
		ProcessCaseTimeEntryLogScheduler m = new ProcessCaseTimeEntryLogScheduler();
		String sch = '0 0 * * * ?';
		Test.startTest();
		String jobID = System.schedule('ProcessCaseTimeEntryLog', sch, m);
		Test.stopTest();
	}

	private static Map<String, pse__Project_Task__c> getProjectTasks(Id projectId) {
		Map<String, pse__Project_Task__c> retMap = new Map<String, pse__Project_Task__c>();
		for(pse__Project_Task__c pTask : [SELECT Id, Name FROM pse__Project_Task__c WHERE pse__Project__c = :projectId]) {
			retMap.put(pTask.Name, pTask);
		}
		
		return retMap;
	}

}
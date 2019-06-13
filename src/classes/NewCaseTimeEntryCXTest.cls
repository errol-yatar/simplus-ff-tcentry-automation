@isTest
public class NewCaseTimeEntryCXTest {
	
	@TestSetup
	public static void createTestData(){
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

			insert new Trigger_Controls__c(Case_Time_Entry_Trigger__c = true, Recurring_Revenue_Renewal_Opp__c = true);
        }

		// Create Region
		pse__Region__c region = (pse__Region__c) TestFactory.createSObject(new pse__Region__c(), true);

		// Create Practice Records
        pse__Grp__c g = (pse__Grp__c) TestFactory.createSObject(new pse__Grp__c(), true);
        
        
        pse__Permission_Control__c pc = (pse__Permission_Control__c) TestFactory.createSObject(new pse__Permission_Control__c(pse__Region__c = region.Id), true);

		// Create resource record for the current running user
		
        Contact c = (Contact)TestFactory.createSObject(new Contact(pse__Allow_Timecards_Without_Assignment__c = true, pse__Region__c = region.Id, 
                                                                   pse__Is_Resource_Active__c = true, pse__Is_Resource__c = true,
                                                                  Revenue_Groups__c = 'Manager', pse__Salesforce_User__c = UserInfo.getUserId()), true);
		
		// Create Account
		Account acct = (Account) TestFactory.createSObject(new Account());

		insert acct;

		// Create Project
		pse__Proj__c proj = (pse__Proj__c) TestFactory.createSObject(new pse__Proj__c(
			pse__Account__c = acct.Id,
			pse__Region__c = region.Id
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
			pse__Salesforce_User__c = u.Id,
			pse__Region__c = region.Id,
			pse__Is_Resource__c = true,
			pse__Is_Resource_Active__c = true,
			pse__Work_Calendar__c = workCalendar.Id,
			pse__Group__c = g.Id,
			RecordTypeId = SObjectType.Contact.getRecordTypeInfosByDeveloperName().get('PSA_Resource').getRecordTypeId(),
			LastName = 'Resource A'
		), true); // Valid resource

		// Create a Project Assignment Schedule
		pse__Schedule__c schedA = (pse__Schedule__c) TestFactory.createSObject(new pse__Schedule__c(pse__Start_Date__c = Date.today().addDays(-7), 
																								pse__End_Date__c = Date.today().addDays(30)), true);

		pse__Assignment__c assignA = (pse__Assignment__c)TestFactory.createSObject(new pse__Assignment__c(pse__Is_Billable__c = true, pse__Resource__c = resourceA.Id,
                                                                                                     pse__Schedule__c = schedA.Id, Product_Family__c = 'Salesforce', 
                                                                                                     pse__Project__c = proj.Id, pse__Bill_Rate__c = 300), true);

		// Create a case
		Case caseA = (Case) TestFactory.createSObject(new Case(
			Subject = 'Case A',
			AccountId = acct.Id,
			Project__c = proj.Id
		), true);
	}

	@isTest
	public static void testNewRecord() {
		Case caseA = [SELECT Id FROM Case WHERE Subject = 'Case A' LIMIT 1];

		PageReference pageRef = Page.NewCaseTimeEntry;
		pageRef.getParameters().put('retUrl', '/');
        Test.setCurrentPage(pageRef);
        
        Apexpages.StandardController sc = new Apexpages.StandardController(new Case_Time_Entry__c(Case__c = caseA.Id));
        NewCaseTimeEntryCX ext = new NewCaseTimeEntryCX(sc);         
        List<SelectOption> selOpts = ext.getTaskTypes();
		ext.projectTaskId = selOpts[0].getValue();
		ext.cteRec.Date__c = Date.today();
		ext.cteRec.Time_Spent__c = 5.25;
		ext.cteRec.Comments__c = 'test comment';
		ext.doRedirect();
		ext.doSaveAndNew(); // This will result to an error because the current user has no assignment to the project
		ext.doCancel();

		User u = [SELECT Id FROM User WHERE LastName = 'Resource A'];
		System.runAs(u) {
			ext.doSaveAndNew();
		}

		System.runAs(new User(Id = UserInfo.getUserId())) {
			delete [SELECT Id FROM GroupMember WHERE UserOrGroupId = :u.Id AND Group.DeveloperName = 'Timecard_Automation_Users'];
		}

		System.runAs(u) {
			ext.doRedirect();
		}
	}

	@isTest
	public static void testEditRecord() {
		Case caseA = [SELECT Id, Project__c FROM Case WHERE Subject = 'Case A' LIMIT 1];

		User u = [SELECT Id FROM User WHERE LastName = 'Resource A'];

		Case_Time_Entry__c cte = new Case_Time_Entry__c(
			Case__c = caseA.Id,
			Date__c = Date.today(),
			Time_Spent__c = 0.25,
			Comments__c = 'asdasdasd',
			Project_Task__c = getProjectTasks(caseA.Project__c).get('Service Delivery').Id
		);
		System.runAs(u) {
			insert cte;
		}

		PageReference pageRef = Page.NewCaseTimeEntry;
		pageRef.getParameters().put('retUrl', '/');
        Test.setCurrentPage(pageRef);
        
		Test.startTest();
        Apexpages.StandardController sc = new Apexpages.StandardController(cte);
        NewCaseTimeEntryCX ext = new NewCaseTimeEntryCX(sc);         
        List<SelectOption> selOpts = ext.getTaskTypes();
		ext.projectTaskId = selOpts[1].getValue();
		ext.cteRec.Date__c = Date.today();
		ext.cteRec.Time_Spent__c = 5.25;
		ext.cteRec.Comments__c = 'test comment';

		System.runAs(u) {
			ext.doSaveAndNew();
		}

		Test.stopTest();
	}

	private static Map<String, pse__Project_Task__c> getProjectTasks(Id projectId) {
		Map<String, pse__Project_Task__c> retMap = new Map<String, pse__Project_Task__c>();
		for(pse__Project_Task__c pTask : [SELECT Id, Name FROM pse__Project_Task__c WHERE pse__Project__c = :projectId]) {
			retMap.put(pTask.Name, pTask);
		}
		
		return retMap;
	}

	@isTest
	public static void testAuraMethods() {
		Case caseA = [SELECT Id, Project__c FROM Case WHERE Subject = 'Case A' LIMIT 1];

		User u = [SELECT Id FROM User WHERE LastName = 'Resource A'];

		Case_Time_Entry__c cte = new Case_Time_Entry__c(
			Case__c = caseA.Id,
			Date__c = Date.today(),
			Time_Spent__c = 0.25,
			Comments__c = 'asdasdasd',
			Project_Task__c = getProjectTasks(caseA.Project__c).get('Service Delivery').Id
		);
		System.runAs(u) {
			insert cte;
		}

		Map<String, String> cteMap = new Map<String, String>();
		Map<String, Object> cteMapObj = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(cte));
		for(String key : cteMapObj.keySet()) {
			if(key != 'attributes') {
				cteMap.put(key, String.valueOf(cteMapObj.get(key)));
			}
		}

		System.debug('--> cteMap: ' + cteMap);

		Test.startTest();
		System.runAs(u) {
			NewCaseTimeEntryCX.getCase(caseA.Id);
			NewCaseTimeEntryCX.getTaskTypes(caseA.Id);
			NewCaseTimeEntryCX.save(cteMap);
		}
		Test.stopTest();
	}
}
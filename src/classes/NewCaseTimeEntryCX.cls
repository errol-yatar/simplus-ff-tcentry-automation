public with sharing class NewCaseTimeEntryCX {
	public Case_Time_Entry__c cteRec {get; set;}
	public Id projectTaskId {get; set;}

	public NewCaseTimeEntryCX(ApexPages.StandardController cont) {
		Case_Time_Entry__c cteRecId = (Case_Time_Entry__c) cont.getRecord();
		if(cteRecId.Id != null) { //edit mode
			this.cteRec = [SELECT Id, Project_Task__c, Date__c, Case__c, Case__r.CaseNumber, Time_Spent__c, Comments__c, Exclude_from_Time_Entry_Automation__c FROM Case_Time_Entry__c WHERE Id = :cteRecId.Id];
			if(cteRec.Project_Task__c != null) {
				projectTaskId = cteRec.Project_Task__c;
			}
		}
		else { //new record mode
			cteRec = cteRecId;
		}
	}

	public PageReference doRedirect() {
		// Check if the current user is part of the timecard automation public group
        List<GroupMember> gm = [SELECT Id FROM GroupMember WHERE UserOrGroupId = :UserInfo.getUserId() AND Group.DeveloperName = 'Timecard_Automation_Users'];
        if(gm.size() == 0) {
			System.debug('Parameters: ' + ApexPages.currentPage().getParameters());
			if(String.isNotBlank(ApexPages.currentPage().getParameters().get('id'))) {
            	return new PageReference('/a1T/e?id=' + ApexPages.currentPage().getParameters().get('id') + '&nooverride=1');
			}
			Case cs;
			if(cteRec.Case__c != null) { // Classic new page
				cs = [SELECT Id, CaseNumber FROM Case WHERE Id = :cteRec.Case__c];
			}
			else if(String.isNotBlank(ApexPages.currentPage().getParameters().get('retURL'))) { // Clone -> Save and New
				cs = [SELECT Id, CaseNumber FROM Case WHERE Id IN (SELECT Case__c FROM Case_Time_Entry__c WHERE Id = :ApexPages.currentPage().getParameters().get('retURL').replace('/',''))];
			}
			return new PageReference('/a1T/e?' + 
				(cs != null ? 'CF00N50000008QhuZ=' + cs.CaseNumber : '') + 
				(cs != null ? '&CF00N50000008QhuZ_lkid=' + cs.Id : '') + 
				(cs != null ? '&retURL=%2F' + cs.Id : '') + 
				'&nooverride=1');
        }
		return null;
	}

	public List<SelectOption> getTaskTypes() {
		List<SelectOption> options = new List<SelectOption>();

		Id projectId = [SELECT Id, Project__c FROM Case WHERE Id = :cteRec.Case__c][0].Project__c;
		if(projectId != null) {
			for(pse__Project_Task__c pt : [SELECT Id, Name FROM pse__Project_Task__c WHERE pse__Project__c = :projectId AND Name LIKE 'Service Delivery%' ORDER BY Name]) {
				options.add(new SelectOption(pt.Id, pt.Name));
			}
			for(pse__Project_Task__c pt : [SELECT Id, Name FROM pse__Project_Task__c WHERE pse__Project__c = :projectId AND (NOT Name LIKE 'Service Delivery%')]) {
				options.add(new SelectOption(pt.Id, pt.Name));
			}
		}

		return options;
	}

	public PageReference doSave() {
		cteRec.Project_Task__c = projectTaskId;
		// This method is only called by the VF Page, so we'll set the Source field to 'Visualforce'
		cteRec.Source__c = 'Visualforce';
		try {
			upsert cteRec;
			return new PageReference(ApexPages.currentPage().getParameters().get('retURL'));
		}
		catch(Exception ex) {
			ApexPages.addMessage(
				new ApexPages.Message(
					ApexPages.Severity.ERROR,'Error while saving Case Time Entry Record: ' + ex.getMessage() + '\n' + ex.getStackTraceString()
				)
			);
			return null;
		}
	}

	public void doSaveAndNew() {
		doSave();
		cteRec = new Case_Time_Entry__c(
			Case__c = cteRec.Case__c
		);
	}

	public PageReference doCancel() {
		return new PageReference(ApexPages.currentPage().getParameters().get('retURL'));
	}

	// Lightning Component methods

	@AuraEnabled
	public static void save(Map<String, String> cte) {
		String cteJSON = JSON.serialize(cte);
		Case_Time_Entry__c cteRec = (Case_Time_Entry__c) JSON.deserialize(cteJSON, Case_Time_Entry__c.class);
		// This method is only called by the Lightning Component, so we'll set the Source field to 'Lightning Component'
		cteRec.Source__c = 'Lightning Component';
		upsert cteRec;
	}

	@AuraEnabled
	public static Case getCase(Id caseId) {
		return [SELECT Id, CaseNumber FROM Case WHERE Id = :caseId];
	}

	@AuraEnabled
	public static List<pse__Project_Task__c> getTaskTypes(Id caseId) {
		Id projectId = [SELECT Id, Project__c FROM Case WHERE Id = :caseId][0].Project__c;
		List<pse__Project_Task__c> ptList = new List<pse__Project_Task__c>();
		if(projectId != null) {
			for(pse__Project_Task__c pt : [SELECT Id, Name FROM pse__Project_Task__c WHERE pse__Project__c = :projectId AND Name LIKE 'Service Delivery%' ORDER BY Name]) {
				ptList.add(pt);
			}
			for(pse__Project_Task__c pt : [SELECT Id, Name FROM pse__Project_Task__c WHERE pse__Project__c = :projectId AND (NOT Name LIKE 'Service Delivery%')]) {
				ptList.add(pt);
			}
		}

		return ptList;
	}
}
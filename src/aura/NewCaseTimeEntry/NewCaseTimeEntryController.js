({
    doInit: function(cmp, evt, hlp) {
        // Set today's date
        var today = $A.localizationService.formatDate(new Date(), "YYYY-MM-DD");
        cmp.set('v.caseTimeEntry.Date__c', today);

        // Prepare the action to load case record
        var action = cmp.get("c.getCase");
        action.setParams({ "caseId": cmp.get("v.recordId") });

        // Configure response handler
        action.setCallback(this, function(resp) {
            var state = resp.getState();
            if (state === "SUCCESS") {
                console.log(resp.getReturnValue());
                cmp.set("v.caseRecord", resp.getReturnValue());
                cmp.set("v.caseTimeEntry.Case__c", resp.getReturnValue().Id);
                cmp.set("v.caseTimeEntry.Source__c", 'Lightning Component');
            } else {
                console.log('Problem getting case, response state: ' + state);
            }
        });
        $A.enqueueAction(action);

        //Get the project tasks
        var projectTasksAction = cmp.get('c.getTaskTypes');
        projectTasksAction.setParams({ "caseId": cmp.get("v.recordId") });

        projectTasksAction.setCallback(this, function(resp) {
            var state = resp.getState();
            if (state === "SUCCESS") {
                console.log('Task types => ' + resp.getReturnValue());
                cmp.set("v.projectTasks", resp.getReturnValue());
                console.log('project tasks: ' + resp.getReturnValue());
                if (cmp.get("v.projectTasks") != null && cmp.get("v.projectTasks") != undefined && cmp.get("v.projectTasks").length > 0) {
                    cmp.set("v.caseTimeEntry.Project_Task__c", cmp.get("v.projectTasks")[0].Id);
                }
            } else {
                console.log('Problem getting project tasks, response state: ' + state);
            }
        });
        $A.enqueueAction(projectTasksAction);
    },

    handleSave: function(cmp, evt, hlp) {
        // Disable the button to prevent double saving
        let btn = evt.getSource();
        btn.set('v.disabled', true);

        // Validate the required fields
        let hasError = false;
        console.log('==> ' + cmp.find('taskType').get('v.value'));
        let fieldNames = ['taskType', 'timeSpent', 'cteDate', 'comments'];
        for (var i in fieldNames) {
            let field = cmp.find(fieldNames[i]);
            if (field.get('v.value') == '' || field.get('v.value') == undefined) {
                hasError = true;
                field.set('v.validity', { valid: false, badInput: true });
                field.showHelpMessageIfInvalid();
            }
        }

        if (hasError) {
            btn.set('v.disabled', false);
            // Prepare a toast UI message
            var errToast = $A.get("e.force:showToast");
            errToast.setParams({
                "title": "Failed to save Case Time Entry Record",
                "message": "Please fill in the required values before saving.",
                "type": "error"
            });

            // Update the UI: close panel, show toast, refresh account page
            errToast.fire();
            return;
        }

        // Initiate save record action
        var saveAction = cmp.get('c.save');
        saveAction.setParams({ 'cte': cmp.get('v.caseTimeEntry') });

        saveAction.setCallback(this, function(resp) {
            var state = resp.getState();
            if (state === "SUCCESS") {
                console.log('Successfully saved case time entry record.');
                // Prepare a toast UI message
                var resultsToast = $A.get("e.force:showToast");
                resultsToast.setParams({
                    "title": "Case Time Entry Saved",
                    "message": "The new case time entry was created.",
                    "type": "success"
                });

                // Update the UI: close panel, show toast, refresh account page
                $A.get("e.force:closeQuickAction").fire();
                resultsToast.fire();
                $A.get("e.force:refreshView").fire();

                btn.set('v.disabled', false);
            } else {
                console.log('Problem saving record, response state: ' + JSON.stringify(resp.getError()));
                // Prepare a toast UI message
                var errToast = $A.get("e.force:showToast");
                errToast.setParams({
                    "title": "Save failed",
                    "message": resp.getError(),
                    "type": "error"
                });

                // Update the UI: close panel, show toast, refresh account page
                errToast.fire();

                // Re-enable the save button
                btn.set('v.disabled', false);
            }
        });
        $A.enqueueAction(saveAction);
    },

    nonBillWarning: function(cmp, evt, hlp) {
        var value = cmp.find('taskType').get('v.value');
        console.log('value: ' + value);
        var text = '';
        var tasks = cmp.get("v.projectTasks")
        for (var i in tasks) {
            if (tasks[i].Id == value) {
                text = tasks[i].Name;
                break;
            }
        }
        console.log('text: ' + text);
        var regex = new RegExp('[nN]on*(-*|\s*)[bB]ill.*', 'g');
        if (text.match(regex) != null) {
            // Prepare a toast UI message
            var alertToast = $A.get("e.force:showToast");
            alertToast.setParams({
                "title": "Reminder",
                "message": 'For non-billable tasks, please seek approval from the CSM of this project before filing this case time entry.',
                "type": "warning",
                "duration": 10000
            });

            // Update the UI: close panel, show toast, refresh account page
            alertToast.fire();
        }
    },

    handleCheck: function(cmp, evt, hlp) {
        var isChecked = evt.getSource().get("v.checked");
        cmp.set("v.caseTimeEntry.Exclude_from_Time_Entry_Automation__c", isChecked);
    }
})
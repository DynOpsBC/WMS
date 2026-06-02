page 72278 "DOPSWHS App Role API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'appRole';
    EntitySetName = 'appRoles';
    SourceTable = "DOPSWHS App Role";
    DelayedInsert = true;
    ODataKeyFields = "Code";
    Caption = 'WMS App Role API';

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(code; Rec.Code) { Caption = 'code'; }
                field(description; Rec.Description) { Caption = 'description'; }
                field(active; Rec.Active) { Caption = 'active'; }
                field(isSystem; Rec."Is System") { Caption = 'isSystem'; }
                field(sortOrder; Rec."Sort Order") { Caption = 'sortOrder'; }
                field(hideTestTools; Rec."Hide Test Tools") { Caption = 'hideTestTools'; }
                field(hideAdminTools; Rec."Hide Admin Tools") { Caption = 'hideAdminTools'; }
                field(memberCount; Rec."Member Count") { Caption = 'memberCount'; Editable = false; }
                field(ruleCount; Rec."Rule Count") { Caption = 'ruleCount'; Editable = false; }
            }
        }
    }
}

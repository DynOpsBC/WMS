table 72037 "DOPSWHS Inventory Approver"
{
    // KIT-014 / KIT-015: users allowed to approve count variances above the
    // tolerance and to post item reclassification journals. The list is only
    // consulted when the related option is switched on in Advanced WMS Setup
    // (default off: the customer's user/authorization matrix is not final yet).
    Caption = 'Inventory Control Approver';
    DataClassification = CustomerContent;
    LookupPageId = "DOPSWHS Inventory Approvers";
    DrillDownPageId = "DOPSWHS Inventory Approvers";

    fields
    {
        field(1; "User ID"; Code[50])
        {
            Caption = 'User ID';
            DataClassification = EndUserIdentifiableInformation;
            TableRelation = User."User Name";
            ValidateTableRelation = false;
            NotBlank = true;

            trigger OnLookup()
            var
                User: Record User;
                UserSelection: Codeunit "User Selection";
            begin
                if UserSelection.Open(User) then
                    Validate("User ID", User."User Name");
            end;

            trigger OnValidate()
            var
                UserSelection: Codeunit "User Selection";
            begin
                UserSelection.ValidateUserName("User ID");
            end;
        }
        field(10; "Approve Reclassification"; Boolean)
        {
            Caption = 'Approve Reclassification';
        }
        field(20; "Approve Count Variance"; Boolean)
        {
            Caption = 'Approve Count Variance';
        }
        field(30; Description; Text[100])
        {
            Caption = 'Description';
        }
    }

    keys
    {
        key(PK; "User ID")
        {
            Clustered = true;
        }
    }
}

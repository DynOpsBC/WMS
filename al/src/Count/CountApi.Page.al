page 72221 "DOPSWHS Count API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'countSheet';
    EntitySetName = 'countSheets';
    SourceTable = "DOPSWHS Count Sheet Header";
    DelayedInsert = true;
    ODataKeyFields = "No.";

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(no; Rec."No.") { Caption = 'no'; }
                field(locationCode; Rec."Location Code") { Caption = 'locationCode'; }
                field(mode; Rec.Mode) { Caption = 'mode'; }
                field(status; Rec.Status) { Caption = 'status'; }
                field(createdDateTime; Rec."Created DateTime") { Caption = 'createdDateTime'; }
                part(lines; "DOPSWHS Count Sheet Line API")
                {
                    Caption = 'lines';
                    EntityName = 'countSheetLine';
                    EntitySetName = 'countSheetLines';
                    SubPageLink = "Sheet No." = field("No.");
                }
            }
        }
    }

    [ServiceEnabled]
    procedure generateLines(): Integer
    var
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
    begin
        exit(CountMgmt.GenerateLines(Rec."No."));
    end;

    [ServiceEnabled]
    procedure addLine(itemNo: Code[20]; variantCode: Code[10]; binCode: Code[20]): Integer
    var
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
    begin
        exit(CountMgmt.AddLine(Rec."No.", itemNo, variantCode, binCode));
    end;

    [ServiceEnabled]
    procedure startRecount()
    begin
        Rec.Status := Rec.Status::InProgress;
        Rec.Modify(true);
    end;

    [ServiceEnabled]
    procedure postSheet()
    var
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
    begin
        CountMgmt.PostSheet(Rec."No.");
    end;
}

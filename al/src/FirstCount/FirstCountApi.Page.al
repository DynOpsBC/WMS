page 72000 "DOPSWHS First Count API"
{
    // Kitoko (22 Eki 2026): terminal İlk Sayım.
    //   POST firstCounts {locationCode, createdBy}
    //   POST firstCounts('IS-…')/Microsoft.NAV.addLine | deleteLine | post
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'firstCount';
    EntitySetName = 'firstCounts';
    SourceTable = "DOPSWHS First Count Header";
    ODataKeyFields = "No.";
    DelayedInsert = true;
    InsertAllowed = true;
    ModifyAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(no; Rec."No.") { Caption = 'no'; Editable = false; }
                field(locationCode; Rec."Location Code") { Caption = 'locationCode'; }
                field(status; Rec.Status) { Caption = 'status'; Editable = false; }
                field(createdBy; Rec."Created By") { Caption = 'createdBy'; }
                field(createdDateTime; Rec."Created DateTime") { Caption = 'createdDateTime'; Editable = false; }
                field(postedDateTime; Rec."Posted DateTime") { Caption = 'postedDateTime'; Editable = false; }
                field(lineCount; Rec."Line Count") { Caption = 'lineCount'; Editable = false; }
                field(binMandatory; BinMandatory) { Caption = 'binMandatory'; Editable = false; }
            }
        }
    }

    var
        BinMandatory: Boolean;

    trigger OnAfterGetRecord()
    var
        Location: Record Location;
    begin
        Rec.CalcFields("Line Count");
        BinMandatory := Location.Get(Rec."Location Code") and Location."Bin Mandatory";
    end;

    trigger OnInsertRecord(BelowxRec: Boolean): Boolean
    begin
        Rec.Insert(true);
        exit(false);
    end;

    [ServiceEnabled]
    procedure addLine(scanId: Text; itemNo: Code[20]; variantCode: Code[10]; binCode: Code[20]; lotNo: Code[50]; unitOfMeasureCode: Code[10]; quantity: Decimal; userId: Code[50]): Integer
    var
        FirstCountMgmt: Codeunit "DOPSWHS First Count Mgmt";
        ScanGuid: Guid;
    begin
        if scanId <> '' then
            Evaluate(ScanGuid, scanId);
        exit(FirstCountMgmt.AddLine(Rec."No.", ScanGuid, itemNo, variantCode, binCode, lotNo, unitOfMeasureCode, quantity, userId));
    end;

    [ServiceEnabled]
    procedure deleteLine(lineNo: Integer)
    var
        FirstCountMgmt: Codeunit "DOPSWHS First Count Mgmt";
    begin
        FirstCountMgmt.DeleteLine(Rec."No.", lineNo);
    end;

    [ServiceEnabled]
    procedure post(userId: Code[50]): Integer
    var
        FirstCountMgmt: Codeunit "DOPSWHS First Count Mgmt";
    begin
        exit(FirstCountMgmt.PostCount(Rec."No.", userId));
    end;
}

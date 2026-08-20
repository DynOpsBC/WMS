page 72088 "DOPSWHS LP API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'licensePlate';
    EntitySetName = 'licensePlates';
    SourceTable = "DOPSWHS LP Header";
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
                field(binCode; Rec."Bin Code") { Caption = 'binCode'; }
                field(status; Rec.Status) { Caption = 'status'; }
                field(parentLpNo; Rec."Parent LP No.") { Caption = 'parentLpNo'; }
                field(templateCode; Rec."LP Template Code") { Caption = 'templateCode'; }
                field(reusable; Reusable) { Caption = 'reusable'; Editable = false; }
                field(sscc; Rec.SSCC) { Caption = 'sscc'; }
                field(assignedDocumentType; Rec."Assigned Document Type") { Caption = 'assignedDocumentType'; }
                field(assignedDocumentNo; Rec."Assigned Document No.") { Caption = 'assignedDocumentNo'; }
                field(weightKg; Rec."Weight kg") { Caption = 'weightKg'; }
                field(lengthCm; Rec."Length cm") { Caption = 'lengthCm'; }
                field(widthCm; Rec."Width cm") { Caption = 'widthCm'; }
                field(heightCm; Rec."Height cm") { Caption = 'heightCm'; }
                field(notes; Rec.Notes) { Caption = 'notes'; }
            }
            part(lines; "DOPSWHS LP Line API")
            {
                Caption = 'lines';
                EntityName = 'licensePlateLine';
                EntitySetName = 'licensePlateLines';
                SubPageLink = "LP No." = field("No.");
            }
        }
    }

    trigger OnOpenPage()
    var
        FilterMgmt: Codeunit "DOPSWHS App Role Filter Mgmt";
        RecRef: RecordRef;
    begin
        RecRef.GetTable(Rec);
        FilterMgmt.ApplyForCurrentUser(RecRef, Enum::"DOPSWHS App Filter Entity"::LicensePlate);
        RecRef.SetTable(Rec);
    end;

    trigger OnAfterGetRecord()
    var
        Template: Record "DOPSWHS LP Template";
    begin
        Reusable := false;
        if (Rec."LP Template Code" <> '') and Template.Get(Rec."LP Template Code") then
            Reusable := Template.Reusable;
    end;

    var
        Reusable: Boolean;

    [ServiceEnabled]
    procedure release()
    var
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        LPMgt.Release(Rec);
    end;

    [ServiceEnabled]
    procedure assign(docType: Enum "DOPSWHS Assigned Doc Type"; docNo: Code[20])
    var
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        LPMgt.Assign(Rec, docType, docNo);
    end;

    [ServiceEnabled]
    procedure unbuild()
    var
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        LPMgt.Unbuild(Rec);
    end;

    [ServiceEnabled]
    procedure transfer(targetLpNo: Code[20]; linesJson: Text)
    var
        TargetLP: Record "DOPSWHS LP Header";
        SourceLine: Record "DOPSWHS LP Line";
        LPMgt: Codeunit "DOPSWHS LP Management";
        Lines: List of [Integer];
        Quantities: Dictionary of [Integer, Decimal];
    begin
        TargetLP.Get(targetLpNo);
        ParseLines(linesJson, Lines, Quantities);
        // Boş linesJson = "tüm içerik": önceden sessizce hiçbir satır
        // taşınmıyordu (boş liste boş döngü) — tüm satırlarla doldur.
        if Lines.Count() = 0 then begin
            SourceLine.SetRange("LP No.", Rec."No.");
            if SourceLine.FindSet() then
                repeat
                    Lines.Add(SourceLine."Line No.");
                until SourceLine.Next() = 0;
        end;
        LPMgt.Transfer(Rec, TargetLP, Lines, Quantities);
    end;

    [ServiceEnabled]
    procedure usePartial(action: Enum "DOPSWHS Partial Use Action"; qty: Decimal; lineNo: Integer)
    var
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        LPMgt.SplitForPartialUse(Rec, action, qty, lineNo);
    end;

    [ServiceEnabled]
    procedure printLabel(printerId: Code[50]; copies: Integer)
    var
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
    begin
        Dispatcher.PrintLPLabel(Rec, printerId, copies);
    end;

    [ServiceEnabled]
    procedure nest(parentLpNo: Code[20])
    var
        ParentLP: Record "DOPSWHS LP Header";
        NestManager: Codeunit "DOPSWHS LP Nest Manager";
    begin
        ParentLP.Get(parentLpNo);
        NestManager.Nest(Rec, ParentLP);
    end;

    [ServiceEnabled]
    procedure unnest()
    var
        NestManager: Codeunit "DOPSWHS LP Nest Manager";
    begin
        NestManager.Unnest(Rec);
    end;

    [ServiceEnabled]
    procedure start(templateCode: Code[20]; locationCode: Code[10]; binCode: Code[20])
    var
        LPMgt: Codeunit "DOPSWHS LP Management";
        NewLP: Record "DOPSWHS LP Header";
    begin
        LPMgt.Build(templateCode, locationCode, binCode, NewLP);
        Rec.Get(NewLP."No.");
    end;

    [ServiceEnabled]
    procedure stop(printLabel: Boolean)
    var
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        LPMgt.Stop(Rec, printLabel);
    end;

    [ServiceEnabled]
    procedure stopToPrinter(printLabel: Boolean; printerId: Code[50])
    var
        LPMgt: Codeunit "DOPSWHS LP Management";
    begin
        LPMgt.Stop(Rec, printLabel, printerId);
    end;

    local procedure ParseLines(LinesJson: Text; var Lines: List of [Integer]; var Quantities: Dictionary of [Integer, Decimal])
    var
        JsonArray: JsonArray;
        JsonToken: JsonToken;
        JsonObject: JsonObject;
        LineToken: JsonToken;
        QtyToken: JsonToken;
        LineNo: Integer;
        Qty: Decimal;
    begin
        if LinesJson = '' then
            exit;
        JsonArray.ReadFrom(LinesJson);
        foreach JsonToken in JsonArray do begin
            JsonObject := JsonToken.AsObject();
            JsonObject.Get('lineNo', LineToken);
            Evaluate(LineNo, Format(LineToken.AsValue()));
            Lines.Add(LineNo);
            if JsonObject.Get('qty', QtyToken) then begin
                Evaluate(Qty, Format(QtyToken.AsValue()));
                Quantities.Add(LineNo, Qty);
            end;
        end;
    end;
}

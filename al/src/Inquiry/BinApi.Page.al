page 72087 "DOPSWHS Bin API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'bin';
    EntitySetName = 'bins';
    SourceTable = Bin;
    DelayedInsert = true;
    ODataKeyFields = "Location Code", Code;
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(locationCode; Rec."Location Code") { Caption = 'locationCode'; }
                field(code; Rec.Code) { Caption = 'code'; }
                field(description; Rec.Description) { Caption = 'description'; }
                field(zoneCode; Rec."Zone Code") { Caption = 'zoneCode'; }
                field(binTypeCode; Rec."Bin Type Code") { Caption = 'binTypeCode'; }
                field(warehouseClassCode; Rec."Warehouse Class Code") { Caption = 'warehouseClassCode'; }
                field(blockMovement; Rec."Block Movement") { Caption = 'blockMovement'; }
                field(binRanking; Rec."Bin Ranking") { Caption = 'binRanking'; }
                field(maximumCubage; Rec."Maximum Cubage") { Caption = 'maximumCubage'; }
                field(maximumWeight; Rec."Maximum Weight") { Caption = 'maximumWeight'; }
                // BADE (25 Eki 2026): yerleştirme hedefi olamama nedeni ('' = uygun;
                // blocked / receive / ship / adjustment) ve operatöre gösterilecek metin.
                field(putAwayBlock; PutAwayBlock) { Caption = 'putAwayBlock'; Editable = false; }
                field(putAwayBlockMessage; PutAwayBlockMessage) { Caption = 'putAwayBlockMessage'; Editable = false; }
            }
        }
    }

    var
        PutAwayBlock: Text[20];
        PutAwayBlockMessage: Text[250];

    trigger OnAfterGetRecord()
    var
        DirectedPutAway: Codeunit "DOPSWHS Directed PutAway";
    begin
        PutAwayBlock := CopyStr(DirectedPutAway.PutAwayTargetBlockReason(Rec), 1, MaxStrLen(PutAwayBlock));
        PutAwayBlockMessage := '';
        if PutAwayBlock <> '' then
            PutAwayBlockMessage := CopyStr(DirectedPutAway.PutAwayTargetBlockMessage(Rec), 1, MaxStrLen(PutAwayBlockMessage));
    end;

    [ServiceEnabled]
    procedure printLabel(printerId: Code[50]; copies: Integer)
    var
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
    begin
        Dispatcher.PrintBinLabel(Rec, printerId, copies);
    end;

    /// <summary>
    /// BADE (25 Eki 2026): printLabel with the bin label design chosen on the
    /// terminal (labelLayouts, kind Bin). Blank layoutCode = printLabel.
    /// </summary>
    [ServiceEnabled]
    procedure printLabelWithLayout(printerId: Code[50]; copies: Integer; layoutCode: Code[20])
    var
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
    begin
        Dispatcher.PrintBinLabelWithLayout(Rec, printerId, copies, layoutCode);
    end;
}

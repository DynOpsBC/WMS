page 72008 "DOPSWHS Quality Result Dialog"
{
    // Result entry for the Pass / Fail actions of the BC quality order pages
    // (same inputs as the terminal's inspect sheet).
    Caption = 'Quality Inspection Result';
    PageType = StandardDialog;
    ApplicationArea = All;
    UsageCategory = None;

    layout
    {
        area(Content)
        {
            group(Inspection)
            {
                Caption = 'Inspection';
                field(QualityOrderNo; QualityOrderNo)
                {
                    ApplicationArea = All;
                    Caption = 'Quality Order No.';
                    Editable = false;
                    ToolTip = 'Specifies the quality order the result is recorded for.';
                }
                field(InspectorField; Inspector)
                {
                    ApplicationArea = All;
                    Caption = 'Inspector';
                    ToolTip = 'Specifies who inspected the stock.';
                }
                field(NotesField; Notes)
                {
                    ApplicationArea = All;
                    Caption = 'Notes';
                    MultiLine = true;
                    ToolTip = 'Specifies the inspection notes.';
                }
            }
            group(Rejection)
            {
                Caption = 'Rejection';
                Visible = IsFail;
                field(RejectReasonField; RejectReason)
                {
                    ApplicationArea = All;
                    Caption = 'Reject Reason';
                    ToolTip = 'Specifies why the stock is rejected.';

                    trigger OnLookup(var Text: Text): Boolean
                    var
                        ReasonCode: Record "Reason Code";
                    begin
                        if Page.RunModal(Page::"Reason Codes", ReasonCode) <> Action::LookupOK then
                            exit(false);
                        Text := ReasonCode.Code;
                        exit(true);
                    end;
                }
                field(QuarantineBinField; QuarantineBin)
                {
                    ApplicationArea = All;
                    Caption = 'Quarantine Bin';
                    ToolTip = 'Specifies the bin the rejected stock must be placed in. Held stock cannot be put away anywhere else.';

                    trigger OnLookup(var Text: Text): Boolean
                    var
                        QualityDecisionMgmt: Codeunit "DOPSWHS Quality Decision Mgmt";
                    begin
                        exit(QualityDecisionMgmt.LookupBin(LocationCode, Text));
                    end;

                    trigger OnValidate()
                    var
                        Bin: Record Bin;
                    begin
                        if (QuarantineBin <> '') and (LocationCode <> '') then
                            Bin.Get(LocationCode, QuarantineBin);
                    end;
                }
            }
        }
    }

    /// <summary>Prepares the dialog for a pass (IsFailResult = false) or fail result of the order.</summary>
    procedure SetOrder(QualityOrder: Record "DOPSWHS Quality Order"; IsFailResult: Boolean)
    begin
        QualityOrderNo := QualityOrder."No.";
        LocationCode := QualityOrder."Location Code";
        IsFail := IsFailResult;
        Inspector := CopyStr(UserId(), 1, MaxStrLen(Inspector));
        QuarantineBin := QualityOrder."Quarantine Bin";
    end;

    procedure GetResult(var InspectorValue: Code[50]; var NotesValue: Text[250]; var RejectReasonValue: Code[20]; var QuarantineBinValue: Code[20])
    begin
        InspectorValue := Inspector;
        NotesValue := Notes;
        RejectReasonValue := RejectReason;
        QuarantineBinValue := QuarantineBin;
    end;

    var
        QualityOrderNo: Code[20];
        LocationCode: Code[10];
        Inspector: Code[50];
        Notes: Text[250];
        RejectReason: Code[20];
        QuarantineBin: Code[20];
        IsFail: Boolean;
}

page 72471 "DOPSWHS EDesp Request Card"
{
    Caption = 'E-Despatch Request (WMS)';
    PageType = Card;
    ApplicationArea = All;
    SourceTable = "DOPSWHS EDesp Request";
    InsertAllowed = false;
    DeleteAllowed = false;
    Editable = false;

    layout
    {
        area(Content)
        {
            group(General)
            {
                Caption = 'General';
                field("Entry No."; Rec."Entry No.") { ApplicationArea = All; ToolTip = 'Specifies the request no.'; }
                field("Source Type"; Rec."Source Type") { ApplicationArea = All; ToolTip = 'Specifies the posted or registered document type.'; }
                field("Source No."; Rec."Source No.") { ApplicationArea = All; ToolTip = 'Specifies the posted or registered document no.'; }
                field("Transfer Order No."; Rec."Transfer Order No.") { ApplicationArea = All; ToolTip = 'Specifies the transfer order.'; }
                field(Status; Rec.Status) { ApplicationArea = All; ToolTip = 'Specifies the status of the e-despatch.'; }
                field("Provider Document No."; Rec."Provider Document No.") { ApplicationArea = All; ToolTip = 'Specifies the e-despatch no.'; }
                field(ETTN; Rec.ETTN) { ApplicationArea = All; ToolTip = 'Specifies the ETTN of the e-despatch.'; }
                field("Provider Status Text"; Rec."Provider Status Text") { ApplicationArea = All; ToolTip = 'Specifies the status reported by the provider.'; }
                field("Last Error"; Rec."Last Error") { ApplicationArea = All; ToolTip = 'Specifies the last error.'; }
                field("Skip Reason"; Rec."Skip Reason") { ApplicationArea = All; ToolTip = 'Specifies why no e-despatch is needed.'; }
            }
            group(Receiver)
            {
                Caption = 'Receiver';
                field("Receiver Type"; Rec."Receiver Type") { ApplicationArea = All; ToolTip = 'Specifies the receiver type.'; }
                field("Receiver No."; Rec."Receiver No.") { ApplicationArea = All; ToolTip = 'Specifies the vendor or customer.'; }
                field("Receiver Name"; Rec."Receiver Name") { ApplicationArea = All; ToolTip = 'Specifies the receiver name.'; }
                field("Receiver Identification No."; Rec."Receiver Identification No.") { ApplicationArea = All; ToolTip = 'Specifies the VKN or TCKN of the receiver.'; }
                field("Receiver Alias"; Rec."Receiver Alias") { ApplicationArea = All; ToolTip = 'Specifies the e-despatch alias of the receiver.'; }
                field("Delivery Address"; Rec."Delivery Address") { ApplicationArea = All; ToolTip = 'Specifies the delivery address.'; }
                field(Purpose; Rec.Purpose) { ApplicationArea = All; ToolTip = 'Specifies the despatch purpose.'; }
                field("Fason Reference No."; Rec."Fason Reference No.") { ApplicationArea = All; ToolTip = 'Specifies the subcontracting reference.'; }
            }
            group(Transport)
            {
                Caption = 'Transport';
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; ToolTip = 'Specifies the location the goods leave.'; }
                field("From Bin Code"; Rec."From Bin Code") { ApplicationArea = All; ToolTip = 'Specifies the bin the goods leave.'; }
                field("To Location Code"; Rec."To Location Code") { ApplicationArea = All; ToolTip = 'Specifies the target location.'; }
                field("To Bin Code"; Rec."To Bin Code") { ApplicationArea = All; ToolTip = 'Specifies the target bin.'; }
                field("Vehicle Plate No."; Rec."Vehicle Plate No.") { ApplicationArea = All; ToolTip = 'Specifies the vehicle plate.'; }
                field("Trailer Plate No."; Rec."Trailer Plate No.") { ApplicationArea = All; ToolTip = 'Specifies the trailer plate.'; }
                field("Driver First Name"; Rec."Driver First Name") { ApplicationArea = All; ToolTip = 'Specifies the driver first name.'; }
                field("Driver Family Name"; Rec."Driver Family Name") { ApplicationArea = All; ToolTip = 'Specifies the driver family name.'; }
                field("Driver Identification No."; Rec."Driver Identification No.") { ApplicationArea = All; ToolTip = 'Specifies the driver TCKN.'; }
                field("Shipping Agent Code"; Rec."Shipping Agent Code") { ApplicationArea = All; ToolTip = 'Specifies the carrier.'; }
                field(Note; Rec.Note) { ApplicationArea = All; ToolTip = 'Specifies the note.'; }
            }
            part(Lines; "DOPSWHS EDesp Request Lines")
            {
                ApplicationArea = All;
                SubPageLink = "Request Entry No." = field("Entry No.");
            }
            group(Audit)
            {
                Caption = 'Audit';
                field("Operator User Id"; Rec."Operator User Id") { ApplicationArea = All; ToolTip = 'Specifies the handheld operator.'; }
                field("Created At"; Rec."Created At") { ApplicationArea = All; ToolTip = 'Specifies when the request was created.'; }
                field("Sent At"; Rec."Sent At") { ApplicationArea = All; ToolTip = 'Specifies when the e-despatch was sent.'; }
                field("Attempt Count"; Rec."Attempt Count") { ApplicationArea = All; ToolTip = 'Specifies how often the provider was called.'; }
                field("Print Count"; Rec."Print Count") { ApplicationArea = All; ToolTip = 'Specifies how often the e-despatch was printed.'; }
                field("Last Printed At"; Rec."Last Printed At") { ApplicationArea = All; ToolTip = 'Specifies when the e-despatch was printed last.'; }
            }
        }
    }
}

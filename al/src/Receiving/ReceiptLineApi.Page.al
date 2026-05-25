page 72227 "DOPSWHS Receipt Line API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'receiptLine';
    EntitySetName = 'receiptLines';
    SourceTable = "Warehouse Receipt Line";
    DelayedInsert = true;
    ODataKeyFields = "No.", "Line No.";

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(no; Rec."No.") { Caption = 'no'; }
                field(lineNo; Rec."Line No.") { Caption = 'lineNo'; }
                field(sourceNo; Rec."Source No.") { Caption = 'sourceNo'; }
                field(sourceLineNo; Rec."Source Line No.") { Caption = 'sourceLineNo'; }
                field(itemNo; Rec."Item No.") { Caption = 'itemNo'; }
                field(description; Rec.Description) { Caption = 'description'; }
                field(unitOfMeasureCode; Rec."Unit of Measure Code") { Caption = 'unitOfMeasureCode'; }
                field(quantity; Rec.Quantity) { Caption = 'quantity'; }
                field(qtyToReceive; Rec."Qty. to Receive") { Caption = 'qtyToReceive'; }
                field(qtyReceived; Rec."Qty. Received") { Caption = 'qtyReceived'; }
                field(binCode; Rec."Bin Code") { Caption = 'binCode'; }
                field(lotNo; Rec."Lot No.") { Caption = 'lotNo'; }
                field(serialNo; Rec."Serial No.") { Caption = 'serialNo'; }
                field(expiryDate; Rec."Expiration Date") { Caption = 'expiryDate'; }
                field(licensePlateNo; Rec."Package No.") { Caption = 'licensePlateNo'; }
            }
        }
    }

    trigger OnModifyRecord(): Boolean
    var
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        ReceiptMgmt.ConfirmLine(Rec, Rec."Qty. to Receive", Rec."Lot No.", Rec."Serial No.", Rec."Expiration Date", CopyStr(Rec."Package No.", 1, 20), Rec."Bin Code");
        exit(false);
    end;
}

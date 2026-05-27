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
                // TODO Sprint H+ post-deploy: bind these fields to item tracking once exposed on the target receipt line surface.
                field(lotNo; LotNo) { Caption = 'lotNo'; }
                field(serialNo; SerialNo) { Caption = 'serialNo'; }
                field(expiryDate; ExpiryDate) { Caption = 'expiryDate'; }
                field(licensePlateNo; LicensePlateNo) { Caption = 'licensePlateNo'; }
            }
        }
    }

    trigger OnModifyRecord(): Boolean
    var
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        ReceiptMgmt.ConfirmLine(Rec, Rec."Qty. to Receive", LotNo, SerialNo, ExpiryDate, LicensePlateNo, Rec."Bin Code");
        exit(false);
    end;

    var
        LotNo: Code[50];
        SerialNo: Code[50];
        ExpiryDate: Date;
        LicensePlateNo: Code[20];
}

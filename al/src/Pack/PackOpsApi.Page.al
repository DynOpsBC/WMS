page 72335 "DOPSWHS Pack Ops API"
{
    // Paketleme istasyonu operasyonları — MovementOps deseninde Setup-singleton
    // üzerinden koleksiyonsuz aksiyonlar:
    //   POST packOps('')/Microsoft.NAV.startSession   {"toteLpNo": "T-06-K2", "mode": "solo|bulk|batch"}
    //   POST packOps('')/Microsoft.NAV.setBox         {"sessionId": 1, "boxLpNo": "", "lpTemplateCode": "CARTON-S"}
    //   POST packOps('')/Microsoft.NAV.setBoxForOrder {"sessionId": 1, "orderNo": "SO-1001", "boxLpNo": "", "lpTemplateCode": ""}
    //   POST packOps('')/Microsoft.NAV.scanItem       {"sessionId": 1, "itemNo": "1000", "qty": 1}
    //   POST packOps('')/Microsoft.NAV.cancelSession  {"sessionId": 1}
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'packOp';
    EntitySetName = 'packOps';
    SourceTable = "DOPSWHS Setup";
    ODataKeyFields = "Primary Key";
    Editable = false;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(primaryKey; Rec."Primary Key") { Caption = 'primaryKey'; Editable = false; }
            }
        }
    }

    [ServiceEnabled]
    procedure startSession(toteLpNo: Code[20]; mode: Text): Integer
    var
        PackMgmt: Codeunit "DOPSWHS Pack Station Mgmt";
    begin
        exit(PackMgmt.StartSession(toteLpNo, mode));
    end;

    // ELOG "ürün-önce": bir PICK'in tüm siparişlerini tek session'da paketle.
    // userId dolu ise paketlemeyi üstlenen WMS operatörü olarak kaydedilir.
    [ServiceEnabled]
    procedure startPickPacking(pickNo: Code[20]; userId: Code[50]): Integer
    var
        PackMgmt: Codeunit "DOPSWHS Pack Station Mgmt";
    begin
        exit(PackMgmt.StartPickSession(pickNo, userId));
    end;

    [ServiceEnabled]
    procedure setBox(sessionId: Integer; boxLpNo: Code[20]; lpTemplateCode: Code[20]): Code[20]
    var
        PackMgmt: Codeunit "DOPSWHS Pack Station Mgmt";
    begin
        exit(PackMgmt.SetBox(sessionId, boxLpNo, lpTemplateCode));
    end;

    // Bulk/batch: kutu sipariş başına — belirli siparişe kutu bağla.
    [ServiceEnabled]
    procedure setBoxForOrder(sessionId: Integer; orderNo: Code[20]; boxLpNo: Code[20]; lpTemplateCode: Code[20]): Code[20]
    var
        PackMgmt: Codeunit "DOPSWHS Pack Station Mgmt";
    begin
        exit(PackMgmt.SetBoxForOrder(sessionId, orderNo, boxLpNo, lpTemplateCode));
    end;

    [ServiceEnabled]
    procedure scanItem(sessionId: Integer; itemNo: Code[20]; qty: Decimal): Text
    var
        PackMgmt: Codeunit "DOPSWHS Pack Station Mgmt";
    begin
        exit(PackMgmt.ScanItem(sessionId, itemNo, qty));
    end;

    [ServiceEnabled]
    procedure cancelSession(sessionId: Integer)
    var
        PackMgmt: Codeunit "DOPSWHS Pack Station Mgmt";
    begin
        PackMgmt.CancelSession(sessionId);
    end;
}

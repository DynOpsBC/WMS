/// <summary>
/// BADE (27 Eki 2026, Merve): WMS kullanıcısı atanırken "Atanan Kullanıcı Kimliği"
/// doğrudan yazılıyor (standart Validate WMS kullanıcısını tanımaz) ve "Atama Tarihi /
/// Saati" boş kalıyordu. Atanan kullanıcı hangi yoldan değişirse değişsin tarih ve
/// saat burada damgalanır; atama kaldırılırsa temizlenir.
/// </summary>
codeunit 72440 "DOPSWHS Assignment Stamp"
{
    Access = Internal;

    [EventSubscriber(ObjectType::Table, Database::"Warehouse Receipt Header", 'OnBeforeModifyEvent', '', false, false)]
    local procedure ReceiptOnBeforeModify(var Rec: Record "Warehouse Receipt Header"; var xRec: Record "Warehouse Receipt Header"; RunTrigger: Boolean)
    var
        Stored: Record "Warehouse Receipt Header";
    begin
        if Rec.IsTemporary() then
            exit;
        if not Stored.Get(Rec."No.") then
            exit;
        if Stored."Assigned User ID" = Rec."Assigned User ID" then
            exit;
        Stamp(Rec."Assigned User ID", Rec."Assignment Date", Rec."Assignment Time");
    end;

    [EventSubscriber(ObjectType::Table, Database::"Warehouse Activity Header", 'OnBeforeModifyEvent', '', false, false)]
    local procedure ActivityOnBeforeModify(var Rec: Record "Warehouse Activity Header"; var xRec: Record "Warehouse Activity Header"; RunTrigger: Boolean)
    var
        Stored: Record "Warehouse Activity Header";
    begin
        if Rec.IsTemporary() then
            exit;
        if not Stored.Get(Rec.Type, Rec."No.") then
            exit;
        if Stored."Assigned User ID" = Rec."Assigned User ID" then
            exit;
        Stamp(Rec."Assigned User ID", Rec."Assignment Date", Rec."Assignment Time");
    end;

    [EventSubscriber(ObjectType::Table, Database::"Warehouse Shipment Header", 'OnBeforeModifyEvent', '', false, false)]
    local procedure ShipmentOnBeforeModify(var Rec: Record "Warehouse Shipment Header"; var xRec: Record "Warehouse Shipment Header"; RunTrigger: Boolean)
    var
        Stored: Record "Warehouse Shipment Header";
    begin
        if Rec.IsTemporary() then
            exit;
        if not Stored.Get(Rec."No.") then
            exit;
        if Stored."Assigned User ID" = Rec."Assigned User ID" then
            exit;
        Stamp(Rec."Assigned User ID", Rec."Assignment Date", Rec."Assignment Time");
    end;

    local procedure Stamp(AssignedUserId: Code[50]; var AssignmentDate: Date; var AssignmentTime: Time)
    begin
        if AssignedUserId = '' then begin
            AssignmentDate := 0D;
            AssignmentTime := 0T;
            exit;
        end;
        AssignmentDate := Today();
        AssignmentTime := Time();
    end;
}

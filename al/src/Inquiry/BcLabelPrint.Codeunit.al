/// <summary>
/// Prints the terminal label designs from Business Central pages: the user
/// picks one of the active ZPL printers, the job goes through the same
/// dispatcher and station routing as a terminal request (DKÇ, 16 Eyl 2026).
/// </summary>
codeunit 72325 "DOPSWHS BC Label Print"
{
    Access = Public;

    var
        SentMsg: Label 'Etiket %1 yazıcısına gönderildi (istasyon %2).', Comment = '%1 printer description, %2 station id';
        NoPrinterErr: Label 'Aktif ZPL etiket yazıcısı yok. Windows yazıcı ajanında "Buluta Eşitle" yapın.';
        ManyLabelsQst: Label 'Seçili %1 madde için %1 ürün etiketi basılacak. Devam edilsin mi?', Comment = '%1 label count';
        ManySentMsg: Label '%1 ürün etiketi %2 yazıcısına gönderildi (istasyon %3).', Comment = '%1 label count, %2 printer description, %3 station id';

    procedure PrintBinLabel(var Bin: Record Bin)
    var
        Printer: Record "DOPSWHS Printer";
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
    begin
        if not PickPrinter(Printer) then
            exit;
        Dispatcher.PrintBinLabel(Bin, Printer.Code, 1);
        Message(SentMsg, Printer.Description, Printer."Station ID");
    end;

    procedure PrintItemLabel(var Item: Record Item)
    var
        Printer: Record "DOPSWHS Printer";
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
    begin
        if not PickPrinter(Printer) then
            exit;
        Dispatcher.PrintItemLabel(Item, Printer.Code, 1);
        Message(SentMsg, Printer.Description, Printer."Station ID");
    end;

    /// <summary>
    /// DKÇ (9 Eki 2026): every selected item of the Item List gets one label.
    /// More than one label asks first, since a full list is ~2,000 labels of roll.
    /// </summary>
    procedure PrintItemLabels(var Item: Record Item)
    var
        Printer: Record "DOPSWHS Printer";
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
        LabelCount: Integer;
        Sent: Integer;
    begin
        LabelCount := Item.Count();
        if LabelCount = 0 then
            exit;
        if LabelCount > 1 then
            if not Confirm(ManyLabelsQst, false, LabelCount) then
                exit;
        if not PickPrinter(Printer) then
            exit;
        Sent := Dispatcher.PrintItemLabels(Item, Printer.Code, 1);
        if Sent = 1 then
            Message(SentMsg, Printer.Description, Printer."Station ID")
        else
            Message(ManySentMsg, Sent, Printer.Description, Printer."Station ID");
    end;

    /// <summary>Lookup over active ZPL printers; a single candidate is used without asking.</summary>
    local procedure PickPrinter(var Printer: Record "DOPSWHS Printer"): Boolean
    var
        PrinterList: Page "DOPSWHS Printer List";
    begin
        Printer.SetRange(Active, true);
        Printer.SetRange(Format, Printer.Format::ZPL);
        if Printer.IsEmpty() then
            Error(NoPrinterErr);
        if Printer.Count() = 1 then begin
            Printer.FindFirst();
            exit(true);
        end;
        PrinterList.SetTableView(Printer);
        PrinterList.LookupMode(true);
        if PrinterList.RunModal() <> Action::LookupOK then
            exit(false);
        PrinterList.GetRecord(Printer);
        exit(true);
    end;
}

codeunit 72200 "DOPSWHS Prepared Label Mgmt"
{
    // No elevated permissions: only a user with write access may replace a list.
    procedure ReplaceList(ListCode: Code[20]; SourceDate: Date; RowsJson: Text): Integer
    var
        Row: Record "DOPSWHS Prepared Label Row";
        Buffer: Record "DOPSWHS Prepared Label Row" temporary;
        Rows: JsonArray;
        Token: JsonToken;
        Value: JsonToken;
        Entry: JsonObject;
        ItemNo: Text;
        BinCode: Text;
        Sequence: Integer;
        Count: Integer;
    begin
        if (ListCode = '') or (SourceDate = 0D) then
            Error('Liste kodu ve kaynak tarihi gereklidir.');
        if StrLen(RowsJson) > 2000000 then
            Error('Liste verisi çok büyük.');
        if not Rows.ReadFrom(RowsJson) then
            Error('Liste satırları okunamadı.');
        if (Rows.Count() = 0) or (Rows.Count() > 10000) then
            Error('Liste 1–10000 satır içermeli.');
        foreach Token in Rows do begin
            Entry := Token.AsObject();
            Entry.Get('order', Value);
            Sequence := Value.AsValue().AsInteger();
            if Sequence <> Count + 1 then
                Error('Liste sırası kesintisiz 1, 2, 3… olmalı.');
            Entry.Get('itemNo', Value);
            ItemNo := Value.AsValue().AsText();
            Entry.Get('bin', Value);
            BinCode := Value.AsValue().AsText();
            if (ItemNo.Trim() = '') or (StrLen(ItemNo) > 20) or (BinCode.Trim() = '') or (StrLen(BinCode) > 20) then
                Error('Satır %1: ürün veya göz bilgisi geçersiz.', Sequence);
            Buffer.Init();
            Buffer."List Code" := ListCode;
            Buffer."Line No." := Sequence;
            Buffer."Source Date" := SourceDate;
            Buffer."Item No." := ItemNo;
            Buffer."Bin Code" := BinCode;
            Buffer.Description := '';
            if Entry.Get('description', Value) then
                Buffer.Description := CopyStr(Value.AsValue().AsText(), 1, MaxStrLen(Buffer.Description));
            Buffer.Insert();
            Count += 1;
        end;
        // All input was validated first; replacement is atomic and restricted to this company/list.
        Row.LockTable();
        Row.SetRange("List Code", ListCode);
        Row.DeleteAll();
        if Buffer.FindSet() then
            repeat
                Row := Buffer;
                Row.Insert();
            until Buffer.Next() = 0;
        exit(Count);
    end;

    procedure ExportList(ListCode: Code[20]): Text
    var
        Row: Record "DOPSWHS Prepared Label Row";
        Rows: JsonArray;
        Entry: JsonObject;
        Result: Text;
    begin
        Row.SetRange("List Code", ListCode);
        if Row.FindSet() then
            repeat
                Clear(Entry);
                Entry.Add('order', Row."Line No.");
                Entry.Add('itemNo', Row."Item No.");
                Entry.Add('description', Row.Description);
                Entry.Add('bin', Row."Bin Code");
                Rows.Add(Entry);
            until Row.Next() = 0;
        Rows.WriteTo(Result);
        exit(Result);
    end;
}

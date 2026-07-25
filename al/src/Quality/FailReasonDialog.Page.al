page 72000 "DOPSWHS Fail Reason Dialog"
{
    // GKK-05: Quality Order Queue'da "Reddet (Fail)" aksiyonu için serbest metin
    // red nedeni girişi. AL'de "Dialog" veri tipinin böyle bir InputQuery metodu
    // yok — bu StandardDialog sayfası gerçek deneme derlemesinde (altool +
    // gerçek BC sembolleri) yakalanan AL0132 hatasının düzeltmesidir.
    PageType = StandardDialog;
    Caption = 'Red Nedeni';
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            field(Notes; NotesValue)
            {
                ApplicationArea = All;
                Caption = 'Red nedeni';
                MultiLine = true;
                NotBlank = true;
                ToolTip = 'Bu Quality Order''ın neden reddedildiğini açıklayın.';
            }
        }
    }

    procedure GetNotes(): Text[250]
    begin
        exit(NotesValue);
    end;

    var
        NotesValue: Text[250];
}

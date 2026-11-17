page 72101 "DOPSWHS Service Technicians"
{
    PageType = List;
    SourceTable = "DOPSWHS Service Technician";
    Caption = 'Service Technicians';
    UsageCategory = Lists;
    ApplicationArea = All;
    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(UserName; Rec."User Name") { ApplicationArea = All; Caption = 'User Name';  }
                field(ResourceNo; Rec."Resource No.") { ApplicationArea = All; Caption = 'Resource No.';  }
                field(ResourceName; Rec."Resource Name") { ApplicationArea = All; Caption = 'Resource Name';  }
                field(Location; Rec."Van Location Code") { ApplicationArea = All; Caption = 'Van Location Code';  }
                field(Active; Rec."Active") { ApplicationArea = All; Caption = 'Active';  }
            }
        }
    }
}

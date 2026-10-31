## Creating a Simple Template

Creating a template is as easy as creating a normal Word document (`.docx`). Yet it could be confusing to people who haven't used the [Mail Merge](https://support.office.com/en-us/article/Use-mail-merge-to-send-bulk-email-messages-0f123521-20ce-4aa8-8b62-ac211dedefa4) feature in Microsoft Word. The steps are as follows:

### Setup
- Create a new word document

![Step 1](/misc/step_1.png)

- Create your template

![Step 2](/misc/step_2.png)

- Add mail merge fields

See [How to add a mail merge field](#how-to-add-a-mail-merge-field) for specific instructions for your operating system.

- You should then have something like this:

![Step 6](/misc/step_6.png)

- A complete template might look like this:

![Step 7](/misc/step_7.png)

NOTE: When adding variables, those that display a value are preceded with an equals sign `=`. Those that just perform logics, such as loops and conditionals, do not need a preceding equals sign.

### How to add a mail merge field

#### Microsoft Windows

- Click the `Insert` tab on the ribbon

![Step 3.1](/misc/step_3_1.png)

- Click the `Quick Parts` dropdown and select `Field...`

![Step 3.2](/misc/step_3_2.png)

- On the dialog, scroll down and select `MergeField`

![Step 3.3a](/misc/step_3_3_a.png)

 - Select `Field Codes`

![Step 3.3b](/misc/step_3_3_b.png)

![Step 4](/misc/step_4.png)

- In the `Field codes` input box, enter your variable in front of the `MERGEFIELD`. Notice the space between the `MERGEFIELD` and the variable

![Step 5](/misc/step_5.png)

#### MacOS
- From the menu bar, open the **Insert** menu and select **Field...**
- Under *Categories*, select **Mail Merge**
- Under *Field names*, select **MergeField**
- Add your variable name in the input box; make sure to leave a space after the word `MERGEFIELD`
  - Example: `MERGEFIELD =person.first_name`
- Click **OK**

## Creating a Spreadsheet Template

Spreadsheet templates are normal Excel workbooks (`.xlsx`). They can be created with Microsoft Excel, LibreOffice Calc or any other application that saves workbooks in the Office Open XML format.

- Create a new workbook and design the sheet as you want the rendered result to look like.
- Type fields into cells using double braces, e.g. `{{=person.first_name}}`. Fields don't need to be inserted using a special dialog; they are normal cell text.
- A field can fill a cell on its own or be part of a longer text like `Dear {{=person.first_name}},`.
- Format the cells that receive values the way the values should be displayed. A cell containing only `{{=invoice.date}}` should use a date format, a cell containing only `{{=item.price}}` a currency format and so on.
- Put the fields of loops and conditionals (`{{items:each(item)}}` ... `{{items:endEach}}`) in their own rows to repeat or remove the rows between them. The rows containing these fields are removed when the template is rendered, so keep them free of other content.
- Put the fields of loops and conditionals in the same row to repeat or remove the cells between them instead.
- Formulas can be used as usual. Write formulas for the first row (or cell) of a loop, e.g. `=B3*C3`. Formulas below a loop like `=SUM(D3)` are extended to all generated rows.

As with Word templates, fields that display a value are preceded with an equals sign `=` while fields that perform logic, such as loops and conditionals, are not.

A complete example can be found in [xlsx_report_template.xlsx](/test/fixtures/xlsx_report_template.xlsx).
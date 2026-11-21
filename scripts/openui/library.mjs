import { createLibrary } from '@openuidev/react-lang';
import { openuiChatLibrary } from '@openuidev/react-ui/genui-lib';

// The official components available to a Development reply.
const names = [
    'Card', 'CardHeader', 'TextContent', 'Separator', 'ListBlock', 'ListItem',
    'Table', 'Col', 'BarChart', 'LineChart', 'HorizontalBarChart', 'Series', 'PieChart', 'Slice',
    'Form', 'FormControl', 'Input', 'TextArea', 'Select', 'SelectItem', 'DatePicker',
    'CheckBoxGroup', 'CheckBoxItem', 'RadioGroup', 'RadioItem', 'Buttons', 'Button',
];

export const library = createLibrary({
    root: 'Card',
    components: names.map(name => openuiChatLibrary.components[name]),
});

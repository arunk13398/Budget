import re

with open('lib/screens/home_screen.dart', 'r') as f:
    content = f.read()

# Add import
if 'import \'package:flip_card/flip_card.dart\';' not in content:
    content = content.replace("import 'package:home_widget/home_widget.dart';", "import 'package:home_widget/home_widget.dart';\nimport 'package:flip_card/flip_card.dart';")

# Revert class definition
content = content.replace('class CardWidgetUI extends StatefulWidget {', 'class CardWidgetUI extends StatelessWidget {')
content = content.replace('  State<CardWidgetUI> createState() => _CardWidgetUIState();\n}\n\nclass _CardWidgetUIState extends State<CardWidgetUI> with SingleTickerProviderStateMixin {', '')

# Remove animation logic
animation_logic_pattern = r'  late AnimationController _controller;\n  late Animation<double> _animation;\n  bool _isFront = true;\n\n  @override\n  void initState\(\) \{\n    super\.initState\(\);\n    _controller = AnimationController\(vsync: this, duration: const Duration\(milliseconds: 600\)\);\n    _animation = Tween<double>\(begin: 0, end: 1\)\.animate\(\n      CurvedAnimation\(parent: _controller, curve: Curves\.easeInOutBack\),\n    \);\n  \}\n\n  @override\n  void dispose\(\) \{\n    _controller\.dispose\(\);\n    super\.dispose\(\);\n  \}\n\n  void _flipCard\(\) \{\n    if \(_isFront\) \{\n      _controller\.forward\(\);\n    \} else \{\n      _controller\.reverse\(\);\n    \}\n    _isFront = !_isFront;\n  \}'
content = re.sub(animation_logic_pattern, '', content)

# Remove `widget.` occurrences inside the class body 
# (To be safe, we just replace `widget.` with `` inside the class scope)
# The class ends roughly at `class ExpenseLineChart extends StatelessWidget {`
class_start = content.find('class CardWidgetUI extends StatelessWidget {')
class_end = content.find('class ExpenseLineChart extends StatelessWidget {')

class_content = content[class_start:class_end]
class_content = class_content.replace('widget.', '')

# Replace build return statement
old_return = '''    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _flipCard,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          final angle = _animation.value * math.pi;
          final isBackVisible = angle > math.pi / 2;

          return Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001) // perspective
              ..rotateX(angle),
            alignment: Alignment.center,
            child: isBackVisible
                ? Transform(
                    transform: Matrix4.identity()..rotateX(math.pi),
                    alignment: Alignment.center,
                    child: _buildBackCard(gradientColors, progress, remaining),
                  )
                : _buildFrontCard(gradientColors, progress, remaining),
          );
        },
      ),
    );'''

new_return = '''    return FlipCard(
      direction: FlipDirection.VERTICAL,
      front: _buildFrontCard(gradientColors, progress, remaining),
      back: _buildBackCard(gradientColors, progress, remaining),
    );'''

class_content = class_content.replace(old_return, new_return)

content = content[:class_start] + class_content + content[class_end:]

with open('lib/screens/home_screen.dart', 'w') as f:
    f.write(content)


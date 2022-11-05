from datetime import date
current_year = date.today().year

project = 'Gridmonger'
copyright = f'2019-{current_year}, John Novak'
author = 'John Novak'

f = open('../../CURRENT_VERSION', 'r')
version = f.readline().strip()
release = version

extensions = ['sphinx.ext.autosectionlabel']

templates_path = ['_templates']

exclude_patterns = ['*.scss']

html_theme = 'gridmonger'
html_theme_path = ['_themes']
html_static_path = ['_static']
html_use_index = False

html_additional_pages = {
  'index': 'index.html'
}

root_doc = 'contents'

autosectionlabel_prefix_document = True

html_context = {
  'current_year': current_year
}

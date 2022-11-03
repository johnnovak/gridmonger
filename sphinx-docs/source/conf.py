project = 'Gridmonger'
copyright = '2019-2022, John Novak'
author = 'John Novak'

release = '2022'

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

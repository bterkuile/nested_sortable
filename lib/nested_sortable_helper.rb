module NestedSortableHelper
  def include_nested_sortable_if_needed
    if @uses_nested_sortable
      stylesheet_link_tag('nestedsortablewidget') +
      javascript_include_tag('interface-1.2.js') +
      javascript_include_tag('json.js') +
      javascript_include_tag('nested_sortable/inestedsortable.js') +
      javascript_include_tag('jquery.nestedsortablewidget.js')
    end
  end
end

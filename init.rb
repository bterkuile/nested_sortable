# Include hook code here
require 'nested_sortable'

class ActionController::Base
  include(NestedSortable::Controller)
end
ActionView::Base.send :include, NestedSortableHelper


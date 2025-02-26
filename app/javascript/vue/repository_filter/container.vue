<template>
  <div class="filters-container" @click="closeDropdowns">
    <div class="header">
      <div id="savedFiltersContainer" class="dropdown saved-filters-container" @click="toggleSavedFilters">
        <div class="title" id="savedFilterDropdown">
          <span class="filter-name">
            {{ filterName || i18n.t('repositories.show.filters.title') }}
          </span>
          <i v-if="savedFilters.length" class="fas fa-caret-down"></i>
        </div>
        <div v-if="savedFilters.length" class="dropdown-menu saved-filters-list">
          <SavedFilterElement
            v-for="(savedFilter, index) in savedFilters"
            :key="savedFilter.id"
            :savedFilter.sync="savedFilters[index]"
            :canManageFilters="canManageFilters"
            @savedFilter:load="loadFilters"
            @savedFilter:delete="savedFilters.splice(index, 1)"
          />
        </div>
      </div>
      <button type="button" class="close" @click="$emit('hide-dropdown')" aria-label="<%= t('general.close') %>">
        <span aria-hidden="true">&times;</span>
      </button>
    </div>
    <FiltersList 
      :filters="filters" 
      :my_modules="my_modules" 
      :key="filterListKey ? 1 : 0"
      @filter:update="updateFilter"
      @filter:delete="deleteFilter" />
    <div class="footer">
      <div id="filtersColumnsDropdown" class="dropup filters-columns-dropdown" @click="toggleColumnsFilters">
        <button class="btn btn-secondary add-filter prevent-shrink" >
          <i class="fas fa-plus"></i>
          {{ i18n.t('repositories.show.filters.add_filter') }}
        </button>
        <div class="dropdown-menu filters-columns-list">

          <ColumnElement
            v-for="(column, index) in columns"
            :key="column.id"
            :column.sync="columns[index]"
            @columns:addFilter="addFilter"
          />
        </div>
      </div>
      <button class="btn btn-secondary clear-filters-btn prevent-shrink" @click="clearFilters">
        {{ i18n.t('repositories.show.filters.clear') }}
      </button>
      <button @click="$emit('filters:apply')" class="btn btn-primary apply-button prevent-shrink">
        {{ i18n.t('repositories.show.filters.apply') }}
      </button>
    </div>
  </div>
</template>

 <script>
  import ColumnElement from 'vue/repository_filter/column.vue'
  import FiltersList from 'vue/repository_filter/filters_list.vue'
  import SavedFilterElement from 'vue/repository_filter/saved_filter.vue'

  export default {
    name: 'FilterContainer',
    props: {
      defaultFilters: Array,
      my_modules: Array,
      container: Object,
      columns: Array,
      savedFilters: Array,
      canManageFilters: Boolean,
      filterName: String, default: () => null
    },
    data() {
      return {
        filters: this.defaultFilters,
        savedFilterScrollbar: null,
        filterListKey: true
      }
    },
    components: { ColumnElement, FiltersList, SavedFilterElement },
    methods: {
      addFilter(column) {
        const id = this.filters.length ? this.filters[this.filters.length - 1].id + 1 : 1
        this.filters.push({ id: id, column: column, isBlank: true, data: {} });
      },
      updateFilter(filter) {
        const index = this.filters.findIndex((f) => f.id === filter.id);
        this.filters[index].data = filter.data;
        this.filters[index].isBlank = filter.isBlank;
        this.$emit("filters:update", this.filters);
      },
      clearFilters() {
        this.$emit('filters:clear');
        this.filterListKey = !this.filterListKey;
      },
      deleteFilter(index) {
        this.filters.splice(index, 1);
      },
      closeDropdowns() {
        this.closeColumnsFilters();
        this.closeSavedFilters();
      },
      closeColumnsFilters() {
        $('#filtersColumnsDropdown').removeClass('open');
      },
      toggleColumnsFilters(e) {
        e.stopPropagation();
        $('.filters-columns-list').scrollTo(0);
        this.closeSavedFilters();
        $('#filtersColumnsDropdown').toggleClass('open');
      },
      loadFilters(filterUrl) {
        this.filters = [];
        $.get(filterUrl, (data) => {
          let filters = [];
          let rawFilters = data.data.attributes.default_columns.concat((data.included || []).map(f => f.attributes))
          let id = 0;
          $.each(rawFilters, (i, f) => {
            filters.push({
              id: id,
              column: this.columns.find(c => c.id == f.repository_column_id),
              isBlank: false,
              data: {
                operator: f.operator,
                parameters: f.parameters
              }
            });
            id++;
          })
          this.$emit('filters:update-current-name', data.data.attributes.name);
          this.filters = filters;

          // set up save modal
          let $saveFiltersModal = $('#modalSaveRepositoryTableFilter');
          let $overwriteLink = $('#overwriteFilterLink');
          $overwriteLink.removeClass('hidden');
          $saveFiltersModal.data('repositoryTableFilterId', data.data.id);
          $('#currentFilterName').html(data.data.attributes.name);
          $saveFiltersModal.data('repositoryTableFilterName', data.data.attributes.name);
        });
      },
      closeSavedFilters() {
        $('#savedFiltersContainer').removeClass('open');
        return true;
      },
      toggleSavedFilters(e) {
        e.stopPropagation();
        $('.saved-filters-list').scrollTo(0);
        if (this.savedFilterScrollbar) {
          this.savedFilterScrollbar.update();
        } else {
          this.savedFilterScrollbar = new PerfectScrollbar($('.saved-filters-list')[0]);
        }
        this.closeColumnsFilters();
        $('#savedFiltersContainer').toggleClass('open');
      },
    }
  }
 </script>

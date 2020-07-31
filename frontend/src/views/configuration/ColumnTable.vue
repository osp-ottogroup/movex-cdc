<template>
  <div>
    <b-table :data="columns"
             striped
             hoverable>
      <template slot-scope="props">
        <b-table-column field="name" label="Columns" searchable>
          <template slot="searchable" slot-scope="props">
            <b-input v-model="props.filters[props.column.field]"
                     icon="magnify"
                     size="is-small"/>
          </template>

          {{ props.row.name }}
        </b-table-column>
        <b-table-column centered field="name" label="Insert-Trigger" searchable>
          <template slot="searchable">
            <div class="icon-wrapper">
              <b-button size="is-small" icon-left="checkbox-multiple-marked-circle-outline" @click="onSelectAll('yn_log_insert')"></b-button>
              <b-button size="is-small" icon-left="checkbox-multiple-blank-circle-outline" @click="onDeselectAll('yn_log_insert')"></b-button>
            </div>
          </template>
          <b-switch size="is-small"
                    true-value="Y"
                    false-value="N"
                    v-model="props.row.yn_log_insert"
                    @input="onColumnChanged(props.row)"/>
        </b-table-column>
        <b-table-column centered field="name" label="Update-Trigger" searchable>
          <template slot="searchable">
            <div class="icon-wrapper">
              <b-button size="is-small" icon-left="checkbox-multiple-marked-circle-outline" @click="onSelectAll('yn_log_update')"></b-button>
              <b-button size="is-small" icon-left="checkbox-multiple-blank-circle-outline" @click="onDeselectAll('yn_log_update')"></b-button>
            </div>
          </template>
          <b-switch size="is-small"
                    true-value="Y"
                    false-value="N"
                    v-model="props.row.yn_log_update"
                    @input="onColumnChanged(props.row)"/>
        </b-table-column>
        <b-table-column centered field="name" label="Delete-Trigger" searchable>
          <template slot="searchable">
            <div class="icon-wrapper">
              <b-button size="is-small" icon-left="checkbox-multiple-marked-circle-outline" @click="onSelectAll('yn_log_delete')"></b-button>
              <b-button size="is-small" icon-left="checkbox-multiple-blank-circle-outline" @click="onDeselectAll('yn_log_delete')"></b-button>
            </div>
          </template>
          <b-switch size="is-small"
                    true-value="Y"
                    false-value="N"
                    v-model="props.row.yn_log_delete"
                    @input="onColumnChanged(props.row)"/>
        </b-table-column>
      </template>
    </b-table>
  </div>
</template>

<script>
export default {
  name: 'ColumnTable',
  props: {
    columns: { type: Array, default: () => [] },
  },
  methods: {
    onColumnChanged(column) {
      this.$emit('column-changed', column);
    },
    onSelectAll(columnProperty) {
      this.$emit('select-all', columnProperty);
    },
    onDeselectAll(columnProperty) {
      this.$emit('deselect-all', columnProperty);
    },
  },
};
</script>

<style lang="scss" scoped>
  ::v-deep table thead tr:nth-child(2) th .th-wrap>span {
    display: block;
    width: 100%;
    .icon-wrapper {
      margin: auto;
      width: 70%;
      button {
        &:first-of-type{
          margin-right: 0.3rem;
        }
        padding: 0 0.2rem;
        span {
          margin: 0;
        }
      }
    }
  }
</style>

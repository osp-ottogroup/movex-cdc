<template>
  <div>
    <b-table :data="columns"
             striped
             hoverable>
      <b-table-column field="name" label="Columns" searchable>
        <template v-slot:searchable="props">
          <b-input v-model="props.filters[props.column.field]"
                   icon="magnify"
                   size="is-small"/>
        </template>
        <template v-slot="props">
          {{ props.row.name }}
          <div v-if="props.row.isDeleted" class="is-size-7 has-text-danger">
            This column doesn't exist in the database anymore. This will lead to errors when generating the triggers.
            <br>
            <a @click="onRemoveColumn(props.row)">Remove now</a>
          </div>
        </template>
      </b-table-column>
      <b-table-column centered field="name" label="Insert-Trigger" searchable>
        <template v-slot:searchable>
          <div class="icon-wrapper" v-if="showSelectButtons">
            <b-tooltip label="Select all columns of table for insert">
              <b-button size="is-small" icon-left="checkbox-multiple-marked-circle-outline" @click="onSelectAll('I')"></b-button>
            </b-tooltip>
            <b-tooltip label="Deselect all columns of table for insert">
              <b-button size="is-small" icon-left="checkbox-multiple-blank-circle-outline" @click="onDeselectAll('I')"></b-button>
            </b-tooltip>
            <b-tooltip label="Add a condition which acts like a Filter for the trigger">
              <b-button size="is-small" :icon-left="conditionIcon('I')" @click="onEditCondition('I')"></b-button>
            </b-tooltip>
          </div>
        </template>
        <template v-slot="props">
          <b-switch size="is-small"
                    true-value="Y"
                    false-value="N"
                    v-model="props.row.yn_log_insert"
                    @input="onColumnChanged(props.row)"/>
        </template>
      </b-table-column>
      <b-table-column centered field="name" label="Update-Trigger" searchable>
        <template v-slot:searchable>
          <div class="icon-wrapper" v-if="showSelectButtons">
            <b-tooltip label="Select all columns of table for update">
              <b-button size="is-small" icon-left="checkbox-multiple-marked-circle-outline" @click="onSelectAll('U')"></b-button>
            </b-tooltip>
            <b-tooltip label="Select all columns of table for update">
              <b-button size="is-small" icon-left="checkbox-multiple-blank-circle-outline" @click="onDeselectAll('U')"></b-button>
            </b-tooltip>
            <b-tooltip label="Add a condition which acts like a Filter for the trigger">
              <b-button size="is-small" :icon-left="conditionIcon('U')" @click="onEditCondition('U')"></b-button>
            </b-tooltip>
          </div>
        </template>
        <template v-slot="props">
          <b-switch size="is-small"
                    true-value="Y"
                    false-value="N"
                    v-model="props.row.yn_log_update"
                    @input="onColumnChanged(props.row)"/>
        </template>
      </b-table-column>
      <b-table-column centered field="name" label="Delete-Trigger" searchable>
        <template v-slot:searchable>
          <div class="icon-wrapper" v-if="showSelectButtons">
            <b-tooltip label="Select all columns of table for delete">
              <b-button size="is-small" icon-left="checkbox-multiple-marked-circle-outline" @click="onSelectAll('D')"></b-button>
            </b-tooltip>
            <b-tooltip label="Select all columns of table for delete">
              <b-button size="is-small" icon-left="checkbox-multiple-blank-circle-outline" @click="onDeselectAll('D')"></b-button>
            </b-tooltip>
            <b-tooltip label="Add a condition which acts like a Filter for the trigger">
              <b-button size="is-small" :icon-left="conditionIcon('D')" @click="onEditCondition('D')"></b-button>
            </b-tooltip>
          </div>
        </template>
        <template v-slot="props">
          <b-switch size="is-small"
                    true-value="Y"
                    false-value="N"
                    v-model="props.row.yn_log_delete"
                    @input="onColumnChanged(props.row)"/>
        </template>
      </b-table-column>
    </b-table>
  </div>
</template>

<script>
export default {
  name: 'ColumnTable',
  props: {
    columns: { type: Array, default: () => [] },
    activeConditionTypes: { type: Object, default: () => {} },
  },
  computed: {
    showSelectButtons() {
      return this.columns.length > 0;
    },
  },
  methods: {
    isConditionActive(type) {
      return this.activeConditionTypes[type] !== undefined;
    },
    conditionIcon(type) {
      return this.isConditionActive(type) ? 'filter-outline' : 'filter-off-outline';
    },
    onColumnChanged(column) {
      this.$emit('column-changed', column);
    },
    onSelectAll(type) {
      this.$emit('select-all', type);
    },
    onDeselectAll(type) {
      this.$emit('deselect-all', type);
    },
    onEditCondition(type) {
      this.$emit('edit-condition', type);
    },
    onRemoveColumn(column) {
      this.$emit('remove-column', column);
    },
  },
};
</script>

<style lang="scss" scoped>
  ::v-deep table thead tr:nth-child(2) th .th-wrap>span {
    display: block;
    width: 100%;
    .icon-wrapper {
      display: flex;
      justify-content: center;
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

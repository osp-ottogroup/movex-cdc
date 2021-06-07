<template>
  <div>
    <b-table :data="schemas"
             :selected.sync="selectedSchema"
             @click="onSchemaSelected">
      <b-table-column field="name" label="Schemas" searchable>
        <template v-slot:searchable="props">
          <b-input v-model="props.filters[props.column.field]"
                   icon="magnify"
                   size="is-small"/>
        </template>

        <template v-slot="props">
          {{ props.row.name }}
          <b-field  v-show="selectedSchema && selectedSchema.id === props.row.id"
                    grouped
                    class="is-pulled-right">
            <div>
              <b-button icon-right="pencil"
                        class="is-small"
                        @click="onEditClicked()" />
            </div>
            <div>
              <b-tooltip label="Show activity log for this schema">
                <b-button icon-right="text-subject" size="is-small" class="ml-1" @click="showActivityLogModal(props.row)"/>
              </b-tooltip>
            </div>
          </b-field>
        </template>
      </b-table-column>

      <template v-slot:empty>
        <div class="content has-text-grey has-text-centered is-size-7">
          <b-icon icon="information" />
          <p v-if="schemas.length === 0">Your user has no authorized schemas.</p>
          <p v-else>No data found.</p>
        </div>
      </template>
    </b-table>

    <template v-if="activityLogModal.show">
      <ActivityLogModal
        :filter="activityLogModal.filter"
        @close="closeActivityLogModal">
      </ActivityLogModal>
    </template>
  </div>
</template>

<script>
import ActivityLogModal from '@/components/ActivityLogModal.vue';

export default {
  name: 'SchemaTable',
  props: {
    schemas: { type: Array, default: () => [] },
  },
  components: {
    ActivityLogModal,
  },
  data() {
    return {
      selectedSchema: null,
      activityLogModal: {
        show: false,
        filter: null,
      },
    };
  },
  methods: {
    onSchemaSelected(schema) {
      this.$emit('schema-selected', schema);
    },
    onEditClicked() {
      this.$emit('edit-schema', this.selectedSchema);
    },
    showActivityLogModal(schema) {
      this.activityLogModal.filter = {
        schemaName: schema.name,
      };
      this.activityLogModal.show = true;
    },
    closeActivityLogModal() {
      this.activityLogModal.filter = null;
      this.activityLogModal.show = false;
    },
  },
  watch: {
    schemas(newList, oldList) {
      if (newList && newList !== oldList && newList.length > 0) {
        // eslint-disable-next-line prefer-destructuring
        this.selectedSchema = newList[0];
      }
      if (newList === oldList) {
        // reference of schema list has not changed
        // it seems that the selected schema has changed, so find changed schema
        const newSchema = newList.find((schema) => schema.id === this.selectedSchema.id);
        this.selectedSchema = newSchema;
      }
      this.$emit('schema-selected', this.selectedSchema);
    },
  },
};
</script>
